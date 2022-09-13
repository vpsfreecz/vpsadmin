require_relative 'pool'

class NodeCurrentStatus < ActiveRecord::Base
  belongs_to :node

  enum pool_state: Pool::STATE_VALUES, _prefix: :state
  enum pool_scan: Pool::SCAN_VALUES, _prefix: :scan

  def pool_state_value
    Pool::STATE_VALUES[ self.class.pool_states[pool_state] ].to_s
  end

  def pool_scan_value
    Pool::SCAN_VALUES[ self.class.pool_scans[pool_scan] ].to_s
  end
end
