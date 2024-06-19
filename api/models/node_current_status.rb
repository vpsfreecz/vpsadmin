require_relative 'pool'

class NodeCurrentStatus < ApplicationRecord
  belongs_to :node

  enum cgroup_version: %i[cgroup_invalid cgroup_v1 cgroup_v2]
  enum pool_state: Pool::STATE_VALUES, _prefix: :state
  enum pool_scan: Pool::SCAN_VALUES, _prefix: :scan

  def pool_state_value
    Pool::STATE_VALUES[self.class.pool_states[pool_state]].to_s
  end

  def pool_scan_value
    Pool::SCAN_VALUES[self.class.pool_scans[pool_scan]].to_s
  end
end
