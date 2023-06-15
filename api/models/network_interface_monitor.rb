class NetworkInterfaceMonitor < ActiveRecord::Base
  self.primary_key = 'network_interface_id'
  belongs_to :network_interface

  def id
    network_interface_id
  end
end
