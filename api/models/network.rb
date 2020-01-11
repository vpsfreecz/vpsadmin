require_relative 'lockable'

class Network < ActiveRecord::Base
  include Lockable

  belongs_to :user
  has_many :location_networks
  has_many :locations, through: :location_networks
  has_many :ip_addresses

  enum role: %i(public_access private_access)
  enum split_access: %i(no_access user_split owner_split)
  enum purpose: %i(any vps export)

  validates :ip_version, inclusion: {
    in: [4, 6],
    messave: '%{value} is not a valid IP version',
  }
  validate :check_ip_integrity

  # @param attrs [Hash]
  # @param opts [Hash]
  # @option opts [Boolean] add_ips
  def self.register!(attrs, opts)
    net = new(attrs)
    chain, _ = TransactionChains::Network::Create.fire(net, opts)
    [chain, net]
  end

  def include?(what)
    case what
    when ::IpAddress
      addr = what.addr

    when ::Network
      addr = what.address
    end

    net_addr { |n| n.include?(IPAddress.parse(addr)) }
  end

  def to_s
    net_addr { |n| n.to_string }
  end

  # Return number of possible IP addresses without network and broadcast address
  def size
    if ip_version == 4
      n = 32
    else
      n = 128
    end

    (2 ** (n - prefix)) / (2 ** (n - split_prefix))
  end

  # Number of IP addresses present in vpsAdmin
  def used
    ip_addresses.count
  end

  # Number of IP addresses assigned to VPSes
  def assigned
    ip_addresses.where.not(network_interface: nil).count
  end

  # Number of IP addresses owned by some users
  def owned
    ip_addresses.where.not(user: nil).count
  end

  # Name of cluster resource appropriate for this network
  def cluster_resource
    return :ipv6 if ip_version == 6
    return :ipv4 if role == 'public_access'
    :ipv4_private
  end

  # @param n [Integer] number of IP addresses to add
  # @param opts [Hash] options
  # @option opts [::User] user owner
  # @option opts [Boolean] lock
  def add_ips(n, opts = {})
    acquire_lock(self) if opts[:lock].nil? || opts[:lock]

    ips = []
    net = net_addr
    last_ip = ip_addresses.order("#{ip_order('ip_addr')} DESC").take
    subsize = subnet_size

    self.class.transaction do
      each_ip(last_ip && last_ip.to_ip) do |host|
        ips << ::IpAddress.register(
          host,
          prefix: split_prefix,
          size: subsize,
          network: self,
          user: opts[:user],
          allocate: false,
        )

        break if ips.count == n
      end

      if opts[:user]
        user_env = opts[:user].environment_user_configs.find_by!(
          environment: location.environment,
        )

        user_env.reallocate_resource!(
          cluster_resource,
          user_env.send(cluster_resource) + (ips.count * subsize),
          user: opts[:user],
          save: true,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )
      end
    end

    ips

  ensure
    release_lock(self) if opts[:lock].nil? || opts[:lock]
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

  def ip_order(col = 'address')
    (ip_version == 4 ? 'INET_ATON' : 'INET6_ATON') + '(' + col + ')'
  end

  # @param from [IPAddress] IPv4/IPv6 address
  def each_ip(from = nil, &block)
    if ip_version == 4
      each_ipv4(from, &block)

    else
      each_ipv6(from, &block)
    end
  end

  # @param from [IPAddress] IPv4 address
  def each_ipv4(from = nil)
    if from
      t = from.broadcast_u32 + 1

    else
      addr = net_addr.network_u32
      t = split_prefix == 32 ? addr + 1 : addr
    end

    last = net_addr.broadcast_u32

    while t < last
      yield(IPAddress::IPv4.parse_u32(t, split_prefix))
      t += 2 ** (32 - split_prefix)
    end
  end

  # @param from [IPAddress] IPv6 address
  def each_ipv6(from = nil)
    if from
      t = from.broadcast_u128 + 1

    else
      addr = net_addr.network_u128
      t = split_prefix == 128 ? addr + 1 : addr
    end

    last = net_addr.broadcast_u128

    while t < last
      yield(IPAddress::IPv6.parse_u128(t, split_prefix))
      t += 2 ** (128 - split_prefix)
    end
  end

  def subnet_size
    if ip_version == 4
      n = 32
    else
      n = 128
    end

    2 ** (n - split_prefix)
  end
end
