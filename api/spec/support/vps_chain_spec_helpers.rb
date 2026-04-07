# frozen_string_literal: true

require 'securerandom'

module VpsChainSpecHelpers
  def ensure_numeric_resources!(user:, environment:)
    {
      cpu: 32,
      memory: 128 * 1024,
      swap: 128 * 1024,
      diskspace: 512 * 1024
    }.each do |resource, value|
      cluster_resource = ClusterResource.find_by!(name: resource.to_s)
      record = UserClusterResource.find_or_initialize_by(
        user: user,
        environment: environment,
        cluster_resource: cluster_resource
      )

      record.value = [record.value.to_i, value].max
      record.save! if record.changed?
    end
  end

  def allocate_dip_diskspace!(dip, user:, value:)
    with_current_context(user: user) do
      dip.allocate_resource!(
        :diskspace,
        value,
        user: user,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        admin_override: true
      )
    end
  end

  def allocate_vps_resources!(vps, user:, cpu: 2, memory: 2048, swap: 0)
    with_current_context(user: user) do
      vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: user,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        values: { cpu: cpu, memory: memory, swap: swap },
        admin_override: true
      )
    end
  end

  def seed_vps_features!(vps)
    VpsFeature::FEATURES.each do |name, feature|
      next unless feature.support?(vps.node)

      VpsFeature.find_or_create_by!(vps: vps, name: name) do |row|
        row.enabled = feature.default?
      end
    end
  end

  def create_network_interface!(vps, name:, kind: :veth_routed, max_tx: 0, max_rx: 0)
    NetworkInterface.create!(
      vps: vps,
      kind: kind,
      name: name,
      max_tx: max_tx,
      max_rx: max_rx
    )
  end

  def create_os_template!(
    distribution: 'specos',
    version: '1',
    vendor: 'spec',
    variant: 'base',
    enabled: true,
    manage_hostname: true,
    manage_dns_resolver: false,
    enable_script: true,
    enable_cloud_init: true,
    cgroup_version: :cgroup_any,
    config: {}
  )
    suffix = SecureRandom.hex(4)

    OsTemplate.create!(
      os_family: SpecSeed.os_family,
      label: "Spec Template #{suffix}",
      distribution: distribution,
      version: version,
      arch: 'x86_64',
      vendor: vendor,
      variant: variant,
      hypervisor_type: :vpsadminos,
      cgroup_version: cgroup_version,
      enabled: enabled,
      manage_hostname: manage_hostname,
      manage_dns_resolver: manage_dns_resolver,
      enable_script: enable_script,
      enable_cloud_init: enable_cloud_init,
      config: config
    )
  end

  def create_vps_user_data!(user:, format:, content:, label: nil)
    VpsUserData.create!(
      user: user,
      label: label || "Spec User Data #{SecureRandom.hex(4)}",
      format: format,
      content: content
    )
  end

  def create_user_public_key!(user:, key:, auto_add:, label: nil)
    UserPublicKey.create!(
      user: user,
      label: label || "Spec Key #{SecureRandom.hex(4)}",
      key: key,
      auto_add: auto_add
    )
  end

  def tx_payload(chain, klass, nth: 0, vps_id: nil)
    tx = transactions_for(chain).select do |row|
      Transaction.for_type(row.handle) == klass && (vps_id.nil? || row.vps_id == vps_id)
    end.fetch(nth)

    JSON.parse(tx.input).fetch('input')
  end

  def confirmation_attr_changes(chain, class_name, confirm_type: nil)
    confirmations_for(chain).select do |row|
      row.class_name == class_name && (confirm_type.nil? || row.confirm_type == confirm_type.to_s)
    end.map(&:attr_changes)
  end
end

RSpec.configure do |config|
  config.include VpsChainSpecHelpers
end
