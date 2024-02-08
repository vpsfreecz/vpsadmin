require_relative 'lockable'

class IpAddress < ActiveRecord::Base
  belongs_to :network
  belongs_to :network_interface
  belongs_to :user
  belongs_to :route_via, class_name: 'HostIpAddress'
  belongs_to :charged_environment, class_name: 'Environment'
  has_many :host_ip_addresses
  has_many :ip_address_assignments

  has_paper_trail

  alias_attribute :addr, :ip_addr

  include Lockable

  validate :check_address
  validate :check_ownership
  validates :ip_addr, uniqueness: true

  # @param addr [IPAddress::IPv4, IPAddress::IPv6]
  # @param params [Hash]
  # @option params [Network] network
  # @option params [User] user
  # @option params [Location] location
  # @option params [Integer] prefix
  # @option params [Integer] size
  # @option params [Boolean] allocate (true)
  def self.register(addr, params)
    ip = nil

    self.transaction do
      if params[:user] && (params[:allocate].nil? || params[:allocate])
        user_env = params[:user].environment_user_configs.find_by!(
          environment: params[:location].environment,
        )
        resource = params[:network].cluster_resource

        user_env.reallocate_resource!(
          resource,
          user_env.send(resource) + params[:size],
          user: params[:user],
          save: true,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed),
        )
      end

      ip = self.create!(
        ip_addr: addr.to_s,
        prefix: params[:prefix],
        size: params[:size],
        network: params[:network],
        user: params[:user]
      )

      HostIpAddress.create!(
        ip_address: ip,
        ip_addr: (addr.ipv4? ? addr.first : addr.take(2).last).to_s,
        order: nil,
      )
    end

    ip
  end

  def version
    network.ip_version
  end

  def free?
    network_interface_id.nil?
  end

  def cluster_resource
    network.cluster_resource
  end

  # Return first free and unlocked IP address version `v` from `location`
  #
  # If option `:address_location` is used, the IP addresses is selected only
  # from networks that are available both in `:location` and `:address_location`.
  #
  # @param opts [Hash]
  # @option opts [::User] :user target user
  # @option opts [::Location] :location target location
  # @option opts [4, 6] :ip_v IP version
  # @option opts [:public_access, :private_access] :role network role
  # @option opts [:any, :vps, :export] :purpose network purpose
  # @option opts [::Location, nil] :address_location
  # @option opts [Array<::Network>] :except_networks
  def self.pick_addr!(opts)
    opts[:role] ||= :public_access
    opts[:purpose] ||= :any

    q = self.select('ip_addresses.*')
      .joins(network: :location_networks)
      .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = ip_addresses.id")
      .where(
        networks: {
          ip_version: opts[:ip_v],
          role: ::Network.roles[opts[:role]],
        },
      )
      .where('network_interface_id IS NULL')
      .where('(ip_addresses.user_id = ? OR ip_addresses.user_id IS NULL)', opts[:user].id)
      .where('rl.id IS NULL')

    if opts[:address_location]
      if ::User.current.role == :admin
        q = q.where(
          networks: {
            id: opts[:location].any_shared_networks_with_primary(
              opts[:address_location],
            ).map(&:id),
          },
        )
      else
        q = q.where(
          networks: {
            id: opts[:location].any_shared_networks_with_primary(
              opts[:address_location],
              userpick: true,
            ).map(&:id),
          },
          location_networks: {
            userpick: true,
          },
        )
      end
    else
      q = q.where(
        location_networks: {
          location_id: opts[:location].id,
          autopick: true,
        },
      )
    end

    if opts[:purpose] != :any
      q = q.where(
        networks: {
          purpose: [
            ::Network.purposes[:any],
            ::Network.purposes[opts[:purpose]],
          ],
        },
      )
    end

    if opts[:except_networks]
      q = q.where.not(network: opts[:except_networks])
    end

    q.order('ip_addresses.user_id DESC, location_networks.priority, ip_addresses.id').take!
  end

  def check_address
    a = ::IPAddress.parse(ip_addr)
    ip_v = network.ip_version

    if (a.ipv4? && ip_v != 4) || (a.ipv6? && ip_v != 6)
      errors.add(:ip_addr, 'IP version does not match the address')

    elsif prefix != network.split_prefix
      errors.add(:ip_addr, "expected /#{network.split_prefix}, got /#{a.prefix}")

    elsif !network.include?(self)
      errors.add(:ip_addr, "does not belong to network #{network}")
    end

  rescue ArgumentError => e
    errors.add(:ip_addr, e.message)
  end

  # @param opts [Hash]
  # @option opts [User] user
  # @option opts [User] environment
  def do_update(opts)
    TransactionChains::Ip::Update.fire(self, opts)
  end

  def check_ownership
    if user && network_interface && user.id != network_interface.vps.user_id
      errors.add(
        :user,
        'can be owned only by the owner of the VPS that uses this address'
      )
    end
  end

  # @return [::User, nil]
  def current_owner
    user || (network_interface && network_interface.vps && network_interface.vps.user)
  end

  def log_assignment(vps:, chain:, confirmable:)
    assignment = ip_address_assignments.create!(
      ip_addr: ip_addr,
      ip_prefix: prefix,
      user: vps.user,
      vps: vps,
      from_date: Time.now,
      to_date: nil,
      assigned_by_chain: chain,
    )

    confirmable.just_create(assignment)
    nil
  end

  def log_unassignment(chain:, confirmable:)
    last_assignment = ip_address_assignments.all.order('id').last

    if last_assignment.nil?
      # This shouldn't be possible unless there's a bug in assignment tracking
      return
    end

    if last_assignment.to_date
      # Again, this shouldn't be possible, but we don't want to raise an exception
      return
    end

    confirmable.edit(last_assignment, to_date: Time.now, unassigned_by_chain_id: chain.id)
    nil
  end

  # @param env [Environment]
  def is_in_environment?(env)
    ::LocationNetwork.joins(:location).where(
      network_id: network_id,
      locations: {environment_id: env.id},
    ).any?
  end

  def include?(what)
    case what
    when ::String
      to_ip.include?(IPAddress.parse(what))

    when ::IPAddress::IPv4, ::IPAddress::IPv6 # gem lib
      to_ip.include?(what)
    end
  end

  def to_ip
    IPAddress.parse("#{addr}/#{prefix}")
  end

  def to_s
    "#{addr}/#{prefix}"
  end
end
