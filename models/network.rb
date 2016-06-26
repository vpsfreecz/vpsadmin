class Network < ActiveRecord::Base
  belongs_to :location
  has_many :ip_addresses

  enum role: %i(public_access private_access)

  validates :ip_version, inclusion: {
      in: [4, 6],
      messave: '%{value} is not a valid IP version',
  }
  validate :check_ip_integrity

  def include?(ip)
    net_addr { |n| n.include?(IPAddress.parse(ip.addr)) }
  end

  def to_s
    net_addr { |n| n.to_string }
  end

  # Return number of possible IP addresses without network and broadcast address
  def size
    net_addr { |n| n.size - 2 }
  end

  # Number of IP addresses present in vpsAdmin
  def used
    ip_addresses.count
  end

  # Number of IP addresses assigned to VPSes
  def assigned
    ip_addresses.where.not(vps: nil).count
  end

  # Number of IP addresses owned by some users
  def owned
    ip_addresses.where.not(user: nil).count
  end

  protected
  def net_addr(force = false)
    if force || @net_addr.nil?
      @net_addr = IPAddress.parse("#{address}/#{prefix}")
    end

    yield(@net_addr)
  end

  def check_ip_integrity
    net_addr(true) do |n|
      ip_addresses.each do |ip|
        unless n.include?(ip.to_ip)
          errors.add(:address, "IP #{ip.addr} does not belong to this network")
        end
      end
    end
  end
end
