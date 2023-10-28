class NetworkInterfaceYearlyAccounting < ActiveRecord::Base
  self.primary_keys = %i(network_interface_id user_id year)
  belongs_to :network_interface
  belongs_to :user
end
