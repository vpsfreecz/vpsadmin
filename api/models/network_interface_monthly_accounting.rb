class NetworkInterfaceMonthlyAccounting < ActiveRecord::Base
  belongs_to :network_interface

  def user
    network_interface.vps.user
  end
end
