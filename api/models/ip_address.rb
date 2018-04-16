class IpAddress < ActiveRecord::Base
  belongs_to :network
  belongs_to :vps, :foreign_key => :vps_id
  belongs_to :user
  has_many :ip_traffics
  has_many :ip_recent_traffics

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
  # @option params [Integer] prefix
  # @option params [Integer] size
  # @option params [Integer] max_tx
  # @option params [Integer] max_rx
  # @option params [Boolean] allocate (true)
  def self.register(addr, params)
    ip = nil

    self.transaction do
      if params[:user] && (params[:allocate].nil? || params[:allocate])
        user_env = params[:user].environment_user_configs.find_by!(
            environment: params[:network].location.environment,
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

      class_id = nil

      begin
        class_id = self.select('ip1.class_id+1 AS first_id')
            .from('ip_addresses ip1')
            .joins('LEFT JOIN ip_addresses ip2 ON ip2.class_id = ip1.class_id + 1')
            .where('ip2.class_id IS NULL')
            .order('ip1.class_id')
            .take!.first_id

      rescue ActiveRecord::RecordNotFound
        class_id = 1
      end

      ip = self.new(
          ip_addr: addr.to_s,
          prefix: params[:prefix],
          size: params[:size],
          network: params[:network],
          class_id: class_id,
          user: params[:user]
      )

      ip.max_tx = params[:max_tx] if params[:max_tx]
      ip.max_rx = params[:max_rx] if params[:max_rx]
      ip.save!
    end

    ip
  end

  def version
    network.ip_version
  end

  def free?
    vps_id.nil? || vps_id == 0
  end

  def cluster_resource
    network.cluster_resource
  end

  # Return first free and unlocked IP address version +v+ from +location+.
  def self.pick_addr!(user, location, v, role = :public_access)
    q = self.select('ip_addresses.*')
      .joins(:network)
      .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = ip_addresses.id")
      .where(networks: {
          ip_version: v,
          location_id: location.id,
          role: ::Network.roles[role],
          autopick: true,
      })
      .where('vps_id IS NULL')
      .where('(ip_addresses.user_id = ? OR ip_addresses.user_id IS NULL)', user.id)
      .where('rl.id IS NULL')
      .order('ip_addresses.user_id DESC, ip_addresses.id').take!
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
  # @option opts [Integer] max_tx
  # @option opts [Integer] max_rx
  # @option opts [User] user
  def do_update(opts)
    TransactionChains::Ip::Update.fire(self, opts)
  end

  def check_ownership
    if user && vps && user.id != vps.user_id
      errors.add(
          :user,
          'can be owned only by the owner of the VPS that uses this address'
      )
    end
  end

  def to_ip
    IPAddress.parse("#{addr}/#{prefix}")
  end

  def to_s
    "#{addr}/#{prefix}"
  end
end
