class Network < ActiveRecord::Base
  belongs_to :location
  has_many :ip_addresses

  enum role: %i(public_access private_access)

  validate :version, inclusion: {
      in: [4, 6],
      messave: '%{value} is not a valid IP version',
  }

  def include?(ip)
    net_addr { |n| n.include?(IPAddress.parse(ip.addr)) }
  end

  def to_s
    net_addr { |n| n.to_string }
  end

  protected
  def net_addr
    @net_addr ||= IPAddress.parse("#{address}/#{prefix}")
    yield(@net_addr)
  end
end
