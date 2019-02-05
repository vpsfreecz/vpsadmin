class Vps < ActiveRecord::Base
  belongs_to :node
  belongs_to :user
  belongs_to :os_template
  belongs_to :dns_resolver
  has_many :transactions

  has_many :network_interfaces
  has_many :ip_addresses, through: :network_interfaces
  has_many :host_ip_addresses, through: :network_interfaces

  has_many :vps_has_configs, -> { order '`order`' }
  has_many :vps_configs, through: :vps_has_configs
  has_many :vps_mounts, dependent: :delete_all
  has_many :vps_features
  has_many :vps_consoles
  has_many :vps_outage_windows

  belongs_to :dataset_in_pool
  has_many :mounts

  has_many :vps_statuses, dependent: :destroy
  has_one :vps_current_status

  has_many :object_histories, as: :tracked_object, dependent: :destroy

  has_paper_trail ignore: %i(maintenance_lock maintenance_lock_reason)

  alias_attribute :veid, :id

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model
  maintenance_parents :node

  include VpsAdmin::API::ClusterResources
  cluster_resources required: %i(cpu memory diskspace),
                    optional: %i(swap),
                    environment: ->(){ node.location.environment }

  include VpsAdmin::API::Lifetimes::Model
  set_object_states suspended: {
                      enter: TransactionChains::Vps::Block,
                      leave: TransactionChains::Vps::Unblock
                    },
                    soft_delete: {
                      enter: TransactionChains::Vps::SoftDelete,
                      leave: TransactionChains::Vps::Revive
                    },
                    hard_delete: {
                      enter: TransactionChains::Vps::Destroy
                    },
                    deleted: {
                      enter: TransactionChains::Lifetimes::NotImplemented
                    },
                    environment: ->(){ node.location.environment }

  include VpsAdmin::API::ObjectHistory::Model
  log_events %i(
      hostname os_template dns_resolver reinstall resources node
      route_add route_del host_addr_add host_addr_del
      start stop restart passwd clone swap configs features mount umount
      outage_windows outage_window restore deploy_public_key netif_rename
  )

  validates :user_id, :node_id, :os_template_id, presence: true, numericality: {only_integer: true}
  validates :hostname, presence: true, format: {
    with: /\A[a-zA-Z\-_\.0-9]{0,255}\z/,
    message: 'bad format'
  }
  validates :cpu_limit, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0
  }, allow_nil: true
  validate :foreign_keys_exist

  default_scope {
    where.not(object_state: object_states[:hard_delete])
  }

  scope :existing, -> {
    unscoped {
      where(object_state: [
              object_states[:active],
              object_states[:suspended]
            ])
    }
  }

  scope :including_deleted, -> {
    unscoped {
      where(object_state: [
              object_states[:active],
              object_states[:suspended],
              object_states[:soft_delete]
            ])
    }
  }

  PathInfo = Struct.new(:dataset, :exists)

  # @param opts [Hash]
  # @option opts [Integer] ipv4
  # @option opts [Integer] ipv6
  # @option opts [Integer] ipv4_private
  def create(opts)
    self.config = ''

    lifetime = self.user.env_config(
      node.location.environment,
      :vps_lifetime
    )

    self.expiration_date = Time.now + lifetime if lifetime != 0

    if valid?
      TransactionChains::Vps::Create.fire(self, opts)
    else
      false
    end
  end

  def destroy(override = false)
    if override
      super
    else
      TransactionChains::Vps::Destroy.fire(self)
    end
  end

  # Filter attributes that must be changed by a transaction.
  def update(attributes)
    TransactionChains::Vps::Update.fire(self, attributes)
  end

  def start
    TransactionChains::Vps::Start.fire(self)
  end

  def restart
    TransactionChains::Vps::Restart.fire(self)
  end

  def stop
    TransactionChains::Vps::Stop.fire(self)
  end

  def applyconfig(configs)
    TransactionChains::Vps::ApplyConfig.fire(self, configs, resources: true)
  end

  def passwd(t)
    pass = generate_password(t)

    [TransactionChains::Vps::Passwd.fire(self, pass).first, pass]
  end

  def reinstall(template)
    TransactionChains::Vps::Reinstall.fire(self, template)
  end

  def restore(snapshot)
    TransactionChains::Vps::Restore.fire(self, snapshot)
  end

  def dataset
    dataset_in_pool.dataset
  end

  %i(is_running uptime process_count cpu_user cpu_nice cpu_system cpu_idle cpu_iowait
     cpu_irq cpu_softirq loadavg used_memory used_swap
  ).each do |attr|
    define_method(attr) do
      vps_current_status && vps_current_status.send(attr)
    end
  end

  alias_method :is_running?, :is_running
  alias_method :running?, :is_running

  def used_diskspace
    dataset_in_pool.referenced
  end

  def migrate(node, opts = {})
    chain_opts = {}

    chain_opts[:replace_ips] = opts[:replace_ip_addresses]
    chain_opts[:outage_window] = opts[:outage_window]
    chain_opts[:send_mail] = opts[:send_mail]
    chain_opts[:reason] = opts[:reason]
    chain_opts[:cleanup_data] = opts[:cleanup_data]

    TransactionChains::Vps::Migrate.chain_for(self, node).fire(self, node, chain_opts)
  end

  def clone(node, attrs)
    TransactionChains::Vps::Clone.chain_for(self, node).fire(self, node, attrs)
  end

  def swap_with(secondary_vps, attrs)
    TransactionChains::Vps::Swap.fire(self, secondary_vps, attrs)
  end

  def mount_dataset(dataset, dst, opts)
    TransactionChains::Vps::MountDataset.fire(self, dataset, dst, opts)
  end

  def mount_snapshot(snapshot, dst, opts)
    TransactionChains::Vps::MountSnapshot.fire(self, snapshot, dst, opts)
  end

  def umount(mnt)
    if mnt.snapshot_in_pool_id
      TransactionChains::Vps::UmountSnapshot.fire(self, mnt)

    else
      TransactionChains::Vps::UmountDataset.fire(self, mnt)
    end
  end

  # @param feature [Symbol]
  # @param enabled [Boolean]
  def set_feature(feature, enabled)
    set_features({feature.name.to_sym => enabled})
  end

  # @param features [Hash<Symbol, Boolean>]
  def set_features(features)
    TransactionChains::Vps::Features.fire(self, build_features(features))
  end

  def deploy_public_key(key)
    TransactionChains::Vps::DeployPublicKey.fire(self, key)
  end

  def has_mount_of?(vps)
    dataset_in_pools = vps.dataset_in_pool.dataset.subtree.joins(
      :dataset_in_pools
    ).where(
      dataset_in_pools: {pool_id: vps.dataset_in_pool.pool_id}
    ).pluck('dataset_in_pools.id')

    snapshot_in_pools = ::SnapshotInPool.where(
      dataset_in_pool_id: dataset_in_pools
    ).pluck('id')

    ::Mount.where(
      'vps_id = ? AND (dataset_in_pool_id IN (?) OR snapshot_in_pool_id IN (?))',
      self.id, dataset_in_pools, snapshot_in_pools
    ).exists?
  end

  def userns
    userns_map.user_namespace
  end

  def userns_map
    dataset_in_pool.user_namespace_map
  end

  private
  def generate_password(t)
    if t == :secure
      chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
      (0..19).map { chars.sample }.join
    else
      chars = ('a'..'z').to_a + (2..9).to_a
      (0..7).map { chars.sample }.join
    end
  end

  def foreign_keys_exist
    User.find(user_id)
    Node.find(node_id)
    OsTemplate.find(os_template_id)
  end

  def prefix_mountpoint(parent, part, mountpoint)
    root = '/'

    return File.join(parent) if parent && !part
    return root unless part

    if mountpoint
      File.join(root, mountpoint)

    elsif parent
      File.join(parent, part.name)
    end
  end

  def dataset_to_destroy(path)
    parts = path.split('/')
    parent = dataset_in_pool.dataset
    dip = nil

    parts.each do |part|
      ds = parent.children.find_by(name: part)

      if ds
        parent = ds
        dip = ds.dataset_in_pools.joins(:pool).where(pools: {role: Pool.roles[:hypervisor]}).take

        unless dip
          raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path
        end

      else
        raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path
      end
    end

    dip
  end

  # @return [Array<VpsFeature>]
  def build_features(features)
    set = vps_features.map do |f|
      n = f.name.to_sym
      f.enabled = features[n] if features.has_key?(n)
      f
    end

    # Check for conflicts
    set.each do |f1|
      set.each do |f2|
        if f1.conflict?(f2)
          raise VpsAdmin::API::Exceptions::VpsFeatureConflict.new(f1, f2)
        end
      end
    end

    set
  end
end
