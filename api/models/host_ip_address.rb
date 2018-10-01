class HostIpAddress < ActiveRecord::Base
  belongs_to :ip_address

  def assigned?
    !order.nil?
  end

  alias_method :assigned, :assigned?

  def version
    ip_address.network.ip_version
  end
end
