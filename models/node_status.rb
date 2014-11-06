class NodeStatus < ActiveRecord::Base
  self.table_name = 'servers_status'
  self.primary_key = 'server_id'
end
