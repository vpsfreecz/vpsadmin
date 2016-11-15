class Network < ActiveRecord::Base
  include Lockable

  belongs_to :location
  belongs_to :user
  has_many :ip_addresses
  
  has_ancestry cache_depth: true

  enum role: %i(public_access private_access)
  enum split_access: %i(no_access user_split owner_split)

  validates :ip_version, inclusion: {
      in: [4, 6],
      messave: '%{value} is not a valid IP version',
  }
  validate :check_ip_integrity
  validate :check_network_integrity

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

    self.class.transaction do
      each_ip(last_ip && last_ip.ip_addr) do |host|
        ips << ::IpAddress.register(
            host.address,
            network: self,
            user: opts[:user],
        )

        break if ips.count == n
      end

      if opts[:user]
        user_env = opts[:user].environment_user_configs.find_by!(
            environment: location.environment,
        )

        user_env.reallocate_resource!(
            cluster_resource,
            user_env.send(cluster_resource) + ips.count,
            user: opts[:user],
            save: true,
            confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )
      end
    end

    ips
  end

  def get_or_create_range(opts)
    self.class.transaction do
      range = ::IpRange.children_of(self).where(user: nil).order(ip_order).take
      attrs = opts.clone

      if range
        if attrs[:user]
          range.user = attrs[:user]
          range.ip_addresses.update_all(user_id: attrs[:user].id)
        end

      else
        net = net_addr
        cnt = ::IpRange.children_of(self).count

        if ip_version == 4
          next_address = IPAddress::IPv4.parse_u32(
              net.to_u32 + (2**(32 - split_prefix)) * cnt
          )

        else
          next_address = IPAddress::IPv6.parse_u128(
              net.to_u128 + (2**(128 - split_prefix)) * cnt
          )
        end

        attrs.update({
            parent: self,
            location: location,
            ip_version: ip_version,
            address: next_address.address,
            prefix: split_prefix,
            role: self.class.roles[role],
            managed: true,
        })

        range = ::IpRange.new(attrs)
      end
      
      if attrs[:user]
        user_env = attrs[:user].environment_user_configs.find_by!(
            environment: location.environment,
        )

        user_env.reallocate_resource!(
            cluster_resource,
            user_env.send(cluster_resource) + range.size,
            user: attrs[:user],
            save: true,
            confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )
      end

      range.save!
      range
    end
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
  
  def check_network_integrity
    return unless parent

    net_addr(true) do |n|
      unless parent.include?(self)
        errors.add(:address, "#{address} is not within parent network #{parent}")
      end
    end
  end

  def ip_order(col = 'address')
    (ip_version == 4 ? 'INET_ATON' : 'INET6_ATON') + '(' + col + ')'
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
