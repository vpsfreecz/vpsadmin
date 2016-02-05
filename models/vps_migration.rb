class VpsMigration < ActiveRecord::Base
  belongs_to :vps
  belongs_to :migration_plan
  belongs_to :transaction_chain
  belongs_to :src_node, class_name: 'Node'
  belongs_to :dst_node, class_name: 'Node'
  belongs_to :user

  enum state: %i(queued running cancelled done error)
end
