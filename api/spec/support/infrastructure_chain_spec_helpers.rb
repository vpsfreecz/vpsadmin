# frozen_string_literal: true

module InfrastructureChainSpecHelpers
  def fresh_node_status!(node, updated_at: Time.now.utc)
    NodeCurrentStatus.find_or_create_by!(node: node) do |status|
      status.vpsadmin_version = 'spec'
      status.kernel = 'spec'
      status.update_count = 1
      status.cgroup_version = :cgroup_v2
      status.pool_state = :online
      status.pool_scan = :none
      status.pool_checked_at = updated_at
      status.created_at = updated_at
      status.updated_at = updated_at
    end.tap do |status|
      status.update!(
        pool_checked_at: updated_at,
        created_at: updated_at,
        updated_at: updated_at
      )
    end
  end

  def stale_node_status!(node)
    fresh_node_status!(node, updated_at: 1.hour.ago.utc)
  end
end

RSpec.configure do |config|
  config.include InfrastructureChainSpecHelpers
end
