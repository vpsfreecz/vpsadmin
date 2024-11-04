class NetworkInterfaceMonthlyAccounting < ApplicationRecord
  self.primary_key = %i[network_interface_id user_id year month]
  belongs_to :network_interface
  belongs_to :user

  def bytes
    bytes_in + bytes_out
  end

  def packets
    packets_in + packets_out
  end

  def sum_bytes
    sum_bytes_in + sum_bytes_out
  end

  def sum_packets
    sum_packets_in + sum_packets_out
  end
end
