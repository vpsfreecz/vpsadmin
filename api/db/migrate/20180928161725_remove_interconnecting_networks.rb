class RemoveInterconnectingNetworks < ActiveRecord::Migration
  def up
    ActiveRecord::Base.connection.execute(
      'DELETE ips FROM ip_addresses ips
       INNER JOIN networks n ON ips.network_id = n.id
       WHERE n.role = 2'
    )
    ActiveRecord::Base.connection.execute(
      'DELETE FROM networks WHERE role = 2'
    )
  end
end
