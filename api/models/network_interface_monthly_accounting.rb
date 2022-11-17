class NetworkInterfaceMonthlyAccounting < ActiveRecord::Base
  belongs_to :network_interface
  belongs_to :user
end
