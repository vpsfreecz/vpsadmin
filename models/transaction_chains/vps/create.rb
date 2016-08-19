module TransactionChains
  class Vps::Create < ::TransactionChain
    label 'Create'

    def link_chain(vps)
      lock(vps.user)
      vps.save!
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps_resources = vps.allocate_resources(
          required: %i(cpu memory swap),
          optional: [],
          user: vps.user,
          chain: self
      )

      pool = vps.node.pools.where(role: :hypervisor).take!

      ds = ::Dataset.new(
          name: vps.id.to_s,
          user: vps.user,
          user_editable: false,
          user_create: true,
          user_destroy: false,
          confirmed: ::Dataset.confirmed(:confirm_create)
      )

      dip = use_chain(Dataset::Create, args: [
          pool,
          nil,
          [ds],
          false,
          {refquota: vps.diskspace},
          vps.user,
          "vps#{vps.id}"
      ]).last

      vps.dataset_in_pool = dip

      lock(vps.dataset_in_pool)

      append(Transactions::Vps::Create, args: vps) do
        create(vps)
        just_create(vps.current_state)

        # Create features
        ::VpsFeature::FEATURES.each_key do |name|
          just_create(::VpsFeature.create!(vps: vps, name: name, enabled: false))
        end

        # Outage windows
        7.times do |i|
          w = VpsOutageWindow.new(
              vps: vps,
              weekday: i,
              is_open: true,
              opens_at: 60,
              closes_at: 5*60,
          )
          w.save!(validate: false)
          just_create(w)
        end
      end

      use_chain(Vps::ApplyConfig, args: [
          vps,
          vps.node.location.environment.vps_configs.pluck(:id)
      ])

      versions = [:ipv4, :ipv4_private]
      versions << :ipv6 if vps.node.location.has_ipv6

      ip_resources = vps.allocate_resources(
          vps.node.location.environment,
          required: [],
          optional: versions,
          user: vps.user,
          chain: self
      )

      if ip_resources.size > 0
        append(Transactions::Utils::NoOp, args: vps.vps_server) do
          ip_resources.each { |r| create(r) }
        end
      end

      vps.dns_resolver ||= ::DnsResolver.pick_suitable_resolver_for_vps(vps)

      append(Transactions::Vps::DnsResolver, args: [
          vps,
          vps.dns_resolver,
          vps.dns_resolver
      ])

      use_chain(Vps::SetResources, args: [vps, vps_resources])

      if vps.vps_onboot
        use_chain(TransactionChains::Vps::Start, args: vps)
      end

      vps.save!

      concerns(:affect, [vps.class.name, vps.id])
    end
  end
end
