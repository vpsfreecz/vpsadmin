class NetworkInterfaceYearlyAccounting < ApplicationRecord
  self.primary_key = %i[network_interface_id user_id year]
  belongs_to :network_interface
  belongs_to :user
end
