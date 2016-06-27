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

  # @param n [Integer] number of IP addresses to add
  # @param opts [Hash] options
  # @option opts [::User] user owner
  def add_ips(n, opts = {})
    cnt = 0
    net = net_addr
    last_ip = ip_addresses.order(
        (ip_version == 4 ? 'INET_ATON' : 'INET6_ATON') + '(ip_addr) DESC'
    ).take

    self.class.transaction do
      each_ip(last_ip && last_ip.ip_addr) do |host|
        ::IpAddress.register(
            host.address,
            network: self,
            user: opts[:user],
        )

        cnt += 1
        break if cnt == n
      end
    end

    cnt
  end

  protected
  def net_addr(force = false)
    if force || @net_addr.nil?
      @net_addr = IPAddress.parse("#{address}/#{prefix}")
    end

    if block_given?
      yield(@net_addr)

    else
      @net_addr
    end
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

  # @param from [String] IPv4/IPv6 address
  def each_ip(from = nil, &block)
    if ip_version == 4
      each_ipv4(from, &block)

    else
      each_ipv6(from, &block)
    end
  end

  # @param from [String] IPv4 address
  def each_ipv4(from = nil)
    addr = (from && IPAddress.parse(from).to_u32) || net_addr.network_u32

    (addr + 1 .. net_addr.broadcast_u32 - 1).each do |i|
      yield(IPAddress::IPv4.parse_u32(i))
    end
  end

  # @param from [String] IPv6 address
  def each_ipv6(from = nil)
    addr = (from && IPAddress.parse(from).to_u128) || net_addr.network_u128

    (addr + 1 .. net_addr.broadcast_u128 - 1).each do |i|
      yield(IPAddress::IPv6.parse_u128(i))
    end
  end
end
