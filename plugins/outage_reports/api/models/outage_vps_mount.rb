class OutageVpsMount < ActiveRecord::Base
  belongs_to :outage_vps
  belongs_to :mount
  belongs_to :src_node, class_name: 'Node'
  belongs_to :src_pool, class_name: 'Pool'
  belongs_to :src_dataset, class_name: 'Dataset'
  belongs_to :src_snapshot, class_name: 'Snapshot'

  def vps_outage
    outage_vps
  end
end
