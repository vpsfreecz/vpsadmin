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

  belongs_to :dataset_in_pool
  has_many :mounts

  has_one :vps_status

  has_paper_trail

  alias_attribute :veid, :vps_id
  alias_attribute :hostname, :vps_hostname
  alias_attribute :user_id, :m_id

  validates :m_id, :vps_server, :vps_template, presence: true, numericality: {only_integer: true}
  validates :vps_hostname, presence: true, format: {
      with: /[a-zA-Z\-_\.0-9]{0,255}/,
      message: 'bad format'
  }
  validate :foreign_keys_exist

  default_scope { where(vps_deleted: nil) }

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model
  maintenance_parent :node

  include VpsAdmin::API::ClusterResources
  cluster_resources required: %i(cpu memory diskspace),
                    optional: %i(ipv4 ipv6 swap)

  PathInfo = Struct.new(:dataset, :exists)

  def create(add_ips)
    self.vps_backup_export = 0 # FIXME
    self.vps_backup_exclude = '' # FIXME
    self.vps_config = ''

    lifetime = self.user.env_config(
        node.environment,
        :vps_lifetime
    )

    self.vps_expiration = Time.new.to_i + lifetime if lifetime != 0

    self.dns_resolver_id ||= DnsResolver.pick_suitable_resolver_for_vps(self).id

    if valid?
      TransactionChains::Vps::Create.fire(self, add_ips)
    else
      false
    end
  end

  def lazy_delete(lazy)
    if lazy
      self.vps_deleted = Time.new.to_i
      save!
      stop
    else
      destroy
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
    assign_attributes(attributes)
    return false unless valid?

    to_change = {}

    %w(vps_hostname vps_template dns_resolver_id).each do |attr|
      if changed.include?(attr)
        if attr.ends_with?('_id')
          to_change[attr] = send("#{attr}_change").map do |id|
            Object.const_get(attr[0..-4].classify).find(id)
          end
        else
          to_change[attr] = send("#{attr}_change")
        end

        send("#{attr}=", changed_attributes[attr])
      end
    end

    unless to_change.empty?
      TransactionChains::Vps::Update.fire(self, to_change)
    end

    (changed? && save) || true
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

  def revive
    self.vps_deleted = nil
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

      raise VpsAdmin::API::Exceptions::IpAddressInUse unless ip.free?

      TransactionChains::Vps::AddIp.fire(self, [ip])
    end
  end

  def add_free_ip(v)
    ::IpAddress.transaction do
      ip = ::IpAddress.pick_addr!(node.location, v)
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

      TransactionChains::Vps::DelIp.fire(self, ips)
    end
  end

  def passwd
    pass = generate_password

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

  def migrate(node)
    TransactionChains::Vps::Migrate.fire(self, node)
  end

  def mount_dataset(dataset, dst, mode)
    TransactionChains::Vps::MountDataset.fire(self, dataset, dst, mode)
  end

  def mount_snapshot(snapshot, dst)
    TransactionChains::Vps::MountSnapshot.fire(self, snapshot, dst)
  end

  def umount(mnt)
    if mnt.dataset_in_pool_id
      TransactionChains::Vps::UmountDataset.fire(self, mnt)

    else
      TransactionChains::Vps::UmountSnapshot.fire(self, mnt)
    end
  end

  private
  def generate_password
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
    (0..19).map { chars.sample }.join
  end

  def foreign_keys_exist
    User.find(user_id)
    Node.find(vps_server)
    OsTemplate.find(vps_template)
    DnsResolver.find(dns_resolver_id)
  end

  def create_default_mounts(mapping)
    VpsMount.default_mounts.each do |m|
      mnt = VpsMount.new(m.attributes)
      mnt.id = nil
      mnt.default = false
      mnt.vps = self if mnt.vps_id == 0 || mnt.vps_id.nil?

      unless m.storage_export_id.nil? || m.storage_export_id == 0
        export = StorageExport.find(m.storage_export_id)

        mnt.storage_export_id = mapping[export.id] if export.default != 'no'
      end

      mnt.save!
    end
  end

  def delete_mounts
    self.vps_mounts.delete(self.vps_mounts.all)
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
