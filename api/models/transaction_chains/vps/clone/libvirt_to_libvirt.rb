require_relative 'base'
require 'securerandom'

module TransactionChains
  # Clone VPS to new VPS
  class Vps::Clone::LibvirtToLibvirt < ::TransactionChain
    label 'Clone'

    include Vps::Clone::Base

    def link_chain(vps, node, attrs)
      lock(vps)

      raise 'Unable to clone to a different node' if node != vps.node

      dst_features = {}
      vps_resources = nil
      confirm_features = []
      confirm_windows = []
      token = SecureRandom.hex(6)

      if attrs[:features]
        vps.vps_features.all.each do |f|
          dst_features[f.name.to_sym] = f.enabled
        end
      end

      dst_vps = ::Vps.new(
        vm_type: vps.vm_type,
        user_id: attrs[:user].id,
        hostname: attrs[:hostname],
        manage_hostname: vps.manage_hostname,
        os_family_id: vps.os_family_id,
        os_template_id: vps.os_template_id,
        info: "Cloned from #{vps.id}. Original info:\n#{vps.info}",
        node_id: node.id,
        onstartall: vps.onstartall,
        cpu_limit: attrs[:resources] ? vps.cpu_limit : nil,
        start_menu_timeout: vps.start_menu_timeout,
        cgroup_version: vps.cgroup_version,
        allow_admin_modifications: vps.allow_admin_modifications,
        enable_os_template_auto_update: vps.enable_os_template_auto_update,
        enable_network: vps.enable_network,
        confirmed: ::Vps.confirmed(:confirm_create)
      )

      ::Uuid.generate_for_new_record! do |uuid|
        dst_vps.uuid = uuid
        dst_vps.save!
        dst_vps
      end

      lifetime = dst_vps.user.env_config(
        dst_vps.node.location.environment,
        :vps_lifetime
      )

      dst_vps.expiration_date = Time.now + lifetime if lifetime != 0

      dst_vps.save!
      lock(dst_vps)

      dst_vps.console_port = ::ConsolePort.reserve!(vps)

      ::VpsFeature::FEATURES.each do |name, f|
        next unless f.support?(dst_vps.node)

        confirm_features << ::VpsFeature.create!(
          vps: dst_vps,
          name:,
          enabled: attrs[:features] && f.support?(vps.node) ? dst_features.fetch(name, false) : false
        )
      end

      # Maintenance windows
      # FIXME: user could choose if he wants to clone it
      vps.vps_maintenance_windows.each do |w|
        w = VpsMaintenanceWindow.new(
          vps: dst_vps,
          weekday: w.weekday,
          is_open: w.is_open,
          opens_at: w.opens_at,
          closes_at: w.closes_at
        )
        w.save!(validate: false)
        confirm_windows << w
      end

      # FIXME: do not fail when there are insufficient resources.
      # It is ok when the available resource is higher than minimum.
      # Perhaps make it a boolean attribute determining if resources
      # must be allocated all or if the available number is sufficient.
      vps_resources = dst_vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: dst_vps.user,
        chain: self,
        values: if attrs[:resources]
                  {
                    cpu: vps.cpu,
                    memory: vps.memory,
                    swap: vps.swap
                  }
                else
                  {}
                end
      )

      use_chain(Vps::Stop, args: [vps])

      dst_vps.storage_volume = use_chain(
        StorageVolume::Clone,
        args: [
          vps.storage_volume,
          ::StoragePool.take_by_node!(node),
          "vps#{dst_vps.id}"
        ]
      )

      lock(dst_vps.storage_volume)
      dst_vps.save!

      concerns(:transform, [vps.class.name, vps.id], [vps.class.name, dst_vps.id])

      append_t(Transactions::Vps::Create, args: [dst_vps]) do |t|
        t.create(dst_vps)

        confirm_features.each do |f|
          t.just_create(f)
        end

        confirm_windows.each do |w|
          t.just_create(w)
        end
      end

      append_t(Transactions::Vps::Define, args: [dst_vps], kwargs: { network_interfaces: [] })

      # Hostname
      clone_hostname(vps, dst_vps, attrs)

      # Resources
      if vps_resources
        use_chain(
          Vps::SetResources,
          args: [dst_vps, vps_resources],
          kwargs: { define_domain: false }
        )
      end

      # IP addresses
      clone_network_interfaces(vps, dst_vps, attrs) unless attrs[:vps]

      # DNS resolver
      dst_vps.dns_resolver = dns_resolver(vps, dst_vps)
      clone_dns_resolver(vps, dst_vps)

      # Start the new VPS
      use_chain(TransactionChains::Vps::Start, args: dst_vps) if vps.running?

      dst_vps.save!
      dst_vps
    end

    def clone_network_interfaces(vps, dst_vps, attrs)
      sums = {
        ipv4: 0,
        ipv4_private: 0,
        ipv6: 0
      }

      # Allocate addresses to interfaces
      vps.network_interfaces.each do |netif|
        dst_netif = use_chain(
          NetworkInterface.chain_for(netif.kind, :Clone),
          args: [netif, dst_vps]
        )

        sums.merge!(clone_ip_addresses(netif, dst_netif, attrs)) do |_key, old_val, new_val|
          old_val + new_val
        end
      end

      # Reallocate cluster resources
      user_env = dst_vps.user.environment_user_configs.find_by!(
        environment: dst_vps.node.location.environment
      )

      changes = sums.map do |r, sum|
        user_env.reallocate_resource!(
          r,
          user_env.send(r) + sum,
          user: dst_vps.user,
          chain: self,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed)
        )
      end

      return unless changes.any?

      append_t(Transactions::Utils::NoOp, args: dst_vps.node_id) do |t|
        changes.each { |use| t.edit(use, { value: use.value }) }
      end
    end

    # Clone IP addresses.
    # Allocates the equal number (or how many are available) of
    # IP addresses.
    def clone_ip_addresses(netif, dst_netif, attrs)
      ips = {
        ipv4: netif.ip_addresses.joins(:network).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:public_access]
          }
        ).count,

        ipv4_private: netif.ip_addresses.joins(:network).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:private_access]
          }
        ).count,

        ipv6: netif.ip_addresses.joins(:network).where(
          networks: { ip_version: 6 }
        ).count
      }

      versions = %i[ipv4 ipv4_private]
      versions << :ipv6 if dst_netif.vps.node.location.has_ipv6

      ret = {}

      versions.each do |r|
        chowned = use_chain(
          Ip::Allocate,
          args: [
            ::ClusterResource.find_by!(name: r),
            dst_netif,
            ips[r]
          ],
          kwargs: {
            strict: false,
            host_addrs: true,
            address_location: attrs[:address_location]
          },
          method: :allocate_to_netif
        )

        ret[r] = chowned
      end

      ret
    end
  end
end
