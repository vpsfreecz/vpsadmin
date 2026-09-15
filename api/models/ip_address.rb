require_relative 'lockable'

class IpAddress < ApplicationRecord
  belongs_to :network
  belongs_to :network_interface
  belongs_to :user
  belongs_to :route_via, class_name: 'HostIpAddress'
  belongs_to :charged_environment, class_name: 'Environment'
  belongs_to :reverse_dns_zone, class_name: 'DnsZone'
  has_many :host_ip_addresses
  has_many :export_hosts
  has_many :ip_address_assignments

  has_paper_trail

  alias_attribute :addr, :ip_addr

  include Lockable

  # Reserve parents in a consistent order before reserving their host records.
  def self.lock_all_current!(chain, ips)
    ordered = ips.uniq(&:id).sort_by(&:id)
    ordered.each { |ip| chain.lock(ip) }
    ordered.each { |ip| ip.lock_current!(chain) }
  end

  # Public entry points must use current ownership after acquiring the resource
  # reservation, even when this chain already reserved another instance.
  def lock_current!(chain, actor: nil)
    chain.lock(self)
    reload(lock: true)
    ensure_owner!(actor) if actor
    self
  end

  # Included chains can explicitly retain an assignment pending confirmation.
  def require_reservation!(chain)
    return if (Array(chain.global_locks) + chain.locks).any? { |reservation| reservation.locks?(self) }

    raise ResourceLocked.new(self, 'IP address is not reserved by this transaction chain')
  end

  def with_current_lock(actor: nil)
    result = nil
    self.class.transaction(requires_new: true) do
      acquire_lock do
        reload(lock: true)
        ensure_owner!(actor) if actor
        result = yield self
      end
    end
    result
  end

  validate :check_address
  validate :check_ownership
  validates :ip_addr, uniqueness: true

  # @param addr [IPAddress::IPv4, IPAddress::IPv6]
  # @param params [Hash]
  # @option params [Network] network
  # @option params [User] user
  # @option params [Location] location
  # @option params [Environment] environment explicit charge environment
  # @option params [Integer] prefix
  # @option params [Integer] size
  # @option params [Boolean] allocate (true)
  def self.register(addr, params)
    ip = nil
    charged_environment = params[:user] && (params[:environment] || params[:location]&.environment)

    raise ArgumentError, 'owned IP addresses require a charge environment' if params[:user] && !charged_environment

    transaction do
      params[:network].lock_for_registration!
      if params[:user] && (params[:allocate].nil? || params[:allocate])
        user_env = params[:user].environment_user_configs.find_by!(
          environment: charged_environment
        )
        resource = params[:network].cluster_resource

        user_env.adjust_resource!(
          resource,
          delta: params[:size],
          user: params[:user],
          save: true,
          confirmed: ::ClusterResourceUse.confirmed(:confirmed)
        )
      end

      reverse_dns_zone = DnsZone.where(zone_role: 'reverse_role').detect do |dns_zone|
        params[:network].include?(dns_zone)
      end

      ip = create!(
        ip_addr: addr.to_s,
        prefix: params[:prefix],
        size: params[:size],
        network: params[:network],
        user: params[:user],
        charged_environment:,
        reverse_dns_zone:
      )

      HostIpAddress.create!(
        ip_address: ip,
        ip_addr: (addr.ipv4? ? addr.first : addr.take(2).last).to_s,
        order: nil
      )
    end

    ip
  end

  def version
    network.ip_version
  end

  # Recheck the actor after taking the IP lock and reloading ownership.
  def ensure_owner!(actor)
    return if actor.role == :admin

    reload_current_assignment! unless user_id
    return if current_owner == actor

    raise VpsAdmin::API::Exceptions::OperationError,
          VpsAdmin::API::I18n.t('errors.access_denied_lower')
  end

  # Assignment can stay unchanged while the VPS owner changes. Use current
  # shared reads so authorization does not inherit an older transaction snapshot.
  def reload_current_assignment!
    network_interface&.reload(lock: 'LOCK IN SHARE MODE')
    network_interface&.vps&.reload(lock: 'LOCK IN SHARE MODE')
    self
  end

  def ensure_charge_environment!
    return unless user_id && !charged_environment_id

    raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation,
          'IP address has no recorded charge environment; reconcile its accounting before changing ownership or assignment'
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
  # @option opts [Environment] :allocation_environment require compatible owned charges for automatic VPS allocation
  def self.pick_addr!(opts)
    pick_scope(opts)
      .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = ip_addresses.id")
      .where('rl.id IS NULL').take!
  end

  # Share selection criteria with the current check made after reservation.
  def self.pick_scope(opts)
    opts[:role] ||= :public_access
    opts[:purpose] ||= :any

    q = self.select('ip_addresses.*')
            .joins(network: :location_networks)
            .where(
              networks: {
                ip_version: opts[:ip_v],
                role: ::Network.roles[opts[:role]]
              }
            )
            .where('network_interface_id IS NULL')
            .where('(ip_addresses.user_id = ? OR ip_addresses.user_id IS NULL)', opts[:user].id)

    if opts[:allocation_environment]
      env = opts[:allocation_environment]
      q = if env.user_ip_ownership
            q.where('ip_addresses.user_id IS NULL OR charged_environment_id IS NULL OR charged_environment_id = ?', env.id)
          else
            q.where(user_id: nil)
          end
    end

    q = if opts[:address_location]
          # Keep both locations in the final query so the locking recheck also
          # sees changes to the primary location's selection policy.
          shared = q.joins('INNER JOIN location_networks primary_locnet ON primary_locnet.network_id = networks.id')
                    .where(location_networks: { location_id: opts[:location].id })
                    .where('primary_locnet.location_id = ? AND primary_locnet.primary = 1', opts[:address_location].id)
                    .where('location_networks.location_id != primary_locnet.location_id')
          if ::User.current.role != :admin
            shared = shared.where(location_networks: { userpick: true }).where('primary_locnet.userpick = 1')
          end
          shared
        else
          q.where(
            location_networks: {
              location_id: opts[:location].id,
              autopick: true
            }
          )
        end

    if opts[:purpose] != :any
      q = q.where(
        networks: {
          purpose: [
            ::Network.purposes[:any],
            ::Network.purposes[opts[:purpose]]
          ]
        }
      )
    end

    q = q.where.not(network: opts[:except_networks]) if opts[:except_networks]

    q.order('ip_addresses.user_id DESC, location_networks.priority, ip_addresses.id')
  end

  def ensure_pickable!(opts)
    ensure_charge_environment!
    return if self.class.pick_scope(opts).where(id:).lock.exists?

    raise VpsAdmin::API::Exceptions::IpAddressInUse,
          'IP address is no longer available for this allocation'
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
    return unless user && network_interface&.vps && user.id != network_interface.vps.user_id

    errors.add(
      :user,
      'can be owned only by the owner of the VPS that uses this address'
    )
  end

  # @return [::User, nil]
  def current_owner
    user || (network_interface && network_interface.vps && network_interface.vps.user)
  end

  def log_assignment(vps:, chain:, confirmable:)
    assignment = ip_address_assignments.create!(
      ip_addr:,
      ip_prefix: prefix,
      user: vps.user,
      vps:,
      from_date: Time.now,
      to_date: nil,
      assigned_by_chain: chain
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
      network_id:,
      locations: { environment_id: env.id }
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
