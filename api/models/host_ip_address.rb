class HostIpAddress < ActiveRecord::Base
  belongs_to :ip_address

  def assigned?
    !order.nil?
  end
end
