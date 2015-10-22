class Vps < ActiveRecord::Base
  self.table_name = 'vps'
  self.primary_key = 'vps_id'

  belongs_to :node, :foreign_key => :vps_server
  belongs_to :user, :foreign_key => :m_id
  belongs_to :os_template, :foreign_key => :vps_template
  belongs_to :dns_resolver
  has_many :ip_addresses
  has_many :transactions, foreign_key: :t_vps

  has_many :vps_has_config, -> { order '`order`' }
  has_many :vps_configs, through: :vps_has_config
  has_many :vps_mounts, dependent: :delete_all
  has_many :vps_features
  has_many :vps_consoles

  belongs_to :dataset_in_pool
  has_many :mounts

  has_one :vps_status

  has_paper_trail ignore: %i(maintenance_lock maintenance_lock_reason)

  alias_attribute :veid, :vps_id
  alias_attribute :hostname, :vps_hostname
  alias_attribute :user_id, :m_id

  validates :m_id, :vps_server, :vps_template, presence: true, numericality: {only_integer: true}
  validates :vps_hostname, presence: true, format: {
      with: /\A[a-zA-Z\-_\.0-9]{0,255}\z/,
      message: 'bad format'
  }
  validate :foreign_keys_exist

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model
  maintenance_parents :node

  include VpsAdmin::API::ClusterResources
  cluster_resources required: %i(cpu memory diskspace),
                    optional: %i(ipv4 ipv6 swap),
                    environment: ->(){ node.environment }

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
                    environment: ->(){ node.environment }

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

  def create
    self.vps_config = ''

    lifetime = self.user.env_config(
        node.environment,
        :vps_lifetime
    )

    self.expiration_date = Time.now + lifetime if lifetime != 0

    self.dns_resolver_id ||= DnsResolver.pick_suitable_resolver_for_vps(self).id

    if valid?
      TransactionChains::Vps::Create.fire(self)
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
    TransactionChains::Vps::ApplyConfig.fire(self, configs)
  end

  # Unless +safe+ is true, the IP address +ip+ is fetched from the database
  # again in a transaction, to ensure that it has not been given
  # to any other VPS. Set +safe+ to true if +ip+ was fetched in a transaction.
  def add_ip(ip, safe = false)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      unless ip.ip_location == node.server_location
        raise VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      end

      if !ip.free? || (ip.user_id && ip.user_id != self.user_id)
        raise VpsAdmin::API::Exceptions::IpAddressInUse
      end

      if !ip.user_id && ::IpAddress.where(
            user: self.user,
            vps: nil,
            ip_location: node.server_location
      ).exists?
        raise VpsAdmin::API::Exceptions::IpAddressNotOwned
      end

      TransactionChains::Vps::AddIp.fire(self, [ip])
    end
  end

  def add_free_ip(v)
    ip = nil

    ::IpAddress.transaction do
      ip = ::IpAddress.pick_addr!(user, node.location, v)
      add_ip(ip, true)
    end

    ip
  end

  # See #add_ip for more information about +safe+.
  def delete_ip(ip, safe = false)
    ::IpAddress.transaction do
      ip = ::IpAddress.find(ip.id) unless safe

      unless ip.vps_id == self.id
        raise VpsAdmin::API::Exceptions::IpAddressNotAssigned
      end

      TransactionChains::Vps::DelIp.fire(self, [ip])
    end
  end

  def delete_ips(v=nil)
    ::IpAddress.transaction do
      if v
        ips = ip_addresses.where(ip_v: v)
      else
        ips = ip_addresses.all
      end

      arr = []
      ips.each { |ip| arr << ip }

      TransactionChains::Vps::DelIp.fire(self, arr)
    end
  end

  def passwd(t)
    pass = generate_password(t)

    TransactionChains::Vps::Passwd.fire(self, pass)

    pass
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

  def running
    vps_status && vps_status.vps_up
  end

  alias_method :running?, :running

  def process_count
    vps_status && vps_status.vps_nproc
  end

  def used_memory
    vps_status && vps_status.vps_vm_used_mb
  end

  def used_disk
    vps_status && vps_status.vps_disk_used_mb
  end

  def migrate(node, replace_ips)
    TransactionChains::Vps::Migrate.fire(self, node, replace_ips)
  end

  def clone(node, attrs)
    TransactionChains::Vps::Clone.fire(self, node, attrs)
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

  def set_feature(feature, enabled)
    set_features({feature.name.to_sym => enabled})
  end

  def set_features(features)
    TransactionChains::Vps::Features.fire(self, features)
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
    Node.find(vps_server)
    OsTemplate.find(vps_template)
    DnsResolver.find(dns_resolver_id)
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
end
