require 'vpsadmin/api/cluster_resources'
require 'vpsadmin/api/lifetimes'
require 'vpsadmin/api/maintainable'
require 'vpsadmin/api/object_history'
require_relative 'confirmable'
require_relative 'lockable'
require_relative 'transaction_chains/vps/block'
require_relative 'transaction_chains/vps/unblock'
require_relative 'transaction_chains/vps/soft_delete'
require_relative 'transaction_chains/vps/revive'
require_relative 'transaction_chains/vps/destroy'
require_relative 'transaction_chains/lifetimes/not_implemented'

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
  has_many :vps_mounts, dependent: :delete_all
  has_many :vps_features
  has_many :vps_consoles
  has_many :vps_maintenance_windows
  has_many :vps_os_processes, dependent: :destroy
  has_many :vps_ssh_host_keys, dependent: :destroy

  belongs_to :user_namespace_map

  belongs_to :dataset_in_pool
  has_one :dataset, through: :dataset_in_pool, autosave: false
  has_many :mounts

  has_many :vps_statuses, dependent: :destroy
  has_one :vps_current_status

  has_many :object_histories, as: :tracked_object, dependent: :destroy
  has_many :oom_reports, dependent: :destroy
  has_many :oom_preventions, dependent: :destroy
  has_many :dataset_expansions

  enum cgroup_version: %i[cgroup_any cgroup_v1 cgroup_v2]

  has_paper_trail ignore: %i[maintenance_lock maintenance_lock_reason]

  alias_attribute :veid, :id

  include Lockable
  include Confirmable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model
  maintenance_parents :node

  include VpsAdmin::API::ClusterResources
  cluster_resources required: %i[cpu memory diskspace],
                    optional: %i[swap],
                    environment: -> { node.location.environment }

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
                    environment: -> { node.location.environment }

  include VpsAdmin::API::ObjectHistory::Model
  log_events %i[
    hostname os_template dns_resolver reinstall resources node
    route_add route_del host_addr_add host_addr_del
    start stop restart passwd clone swap configs features mount umount
    maintenance_windows maintenance_window restore deploy_public_key
    netif_rename start_menu user
  ]

  validates :user_id, :node_id, :os_template_id, presence: true, numericality: { only_integer: true }
  validates :hostname, presence: true, format: {
    with: /\A[a-zA-Z0-9][a-zA-Z\-_.0-9]{0,62}[a-zA-Z0-9]\z/,
    message: 'bad format'
  }
  validates :cpu_limit, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0
  }, allow_nil: true
  validates :start_menu_timeout, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 24 * 60 * 60
  }
  validates :autostart_priority, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0
  }
  validate :foreign_keys_exist
  validate :check_cgroup_version

  default_scope do
    where.not(object_state: object_states[:hard_delete])
  end

  scope :existing, lambda {
    unscoped do
      where(object_state: [
              object_states[:active],
              object_states[:suspended]
            ])
    end
  }

  scope :including_deleted, lambda {
    unscoped do
      where(object_state: [
              object_states[:active],
              object_states[:suspended],
              object_states[:soft_delete]
            ])
    end
  }

  PathInfo = Struct.new(:dataset, :exists)

  # @param opts [Hash]
  # @option opts [Integer] ipv4
  # @option opts [Integer] ipv6
  # @option opts [Integer] ipv4_private
  # @Option opts [::Location, nil] address_location
  # @Option opts [Boolean] start
  def create(opts)
    lifetime = user.env_config(
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

  def passwd(t)
    pass = generate_password(t)

    [TransactionChains::Vps::Passwd.fire(self, pass).first, pass]
  end

  def boot(template, **opts)
    TransactionChains::Vps::Boot.fire(self, template, **opts)
  end

  def reinstall(template)
    TransactionChains::Vps::Reinstall.fire(self, template)
  end

  def restore(snapshot)
    TransactionChains::Vps::Restore.fire(self, snapshot)
  end

  def pool
    dataset_in_pool.pool
  end

  %i[is_running in_rescue_mode uptime process_count cpu_user cpu_nice cpu_system
     cpu_idle cpu_iowait cpu_irq cpu_softirq loadavg used_memory used_swap].each do |attr|
    define_method(attr) do
      vps_current_status && vps_current_status.send(attr)
    end
  end

  alias is_running? is_running
  alias running? is_running

  def rootfs_diskspace
    dataset_in_pool.diskspace(default: false)
  end

  def used_diskspace
    dataset_in_pool.referenced
  end

  def migrate(node, opts = {})
    chain_opts = {}

    chain_opts[:replace_ips] = opts[:replace_ip_addresses]
    chain_opts[:transfer_ips] = opts[:transfer_ip_addresses]
    chain_opts[:swap] = opts[:swap] && opts[:swap].to_sym
    chain_opts[:maintenance_window] = opts[:maintenance_window]
    chain_opts[:finish_weekday] = opts[:finish_weekday]
    chain_opts[:finish_minutes] = opts[:finish_minutes]
    chain_opts[:send_mail] = opts[:send_mail]
    chain_opts[:reason] = opts[:reason]
    chain_opts[:cleanup_data] = opts[:cleanup_data]
    chain_opts[:no_start] = opts[:no_start]
    chain_opts[:skip_start] = opts[:skip_start]

    TransactionChains::Vps::Migrate.chain_for(self, node).fire(self, node, chain_opts)
  end

  def clone(node, attrs)
    TransactionChains::Vps::Clone.chain_for(self, node).fire(self, node, attrs)
  end

  def swap_with(secondary_vps, attrs)
    TransactionChains::Vps::Swap.fire(self, secondary_vps, attrs)
  end

  def replace(node, attrs)
    TransactionChains::Vps::Replace.chain_for(self, node).fire(self, node, attrs)
  end

  def mount_dataset(dataset, dst, opts)
    TransactionChains::Vps::MountDataset.fire(self, dataset, dst, opts)
  end

  def umount(mnt)
    raise 'snapshot mounts are not supported' if mnt.snapshot_in_pool_id

    TransactionChains::Vps::UmountDataset.fire(self, mnt)
  end

  # @param feature [Symbol]
  # @param enabled [Boolean]
  def set_feature(feature, enabled)
    set_features({ feature.name.to_sym => enabled })
  end

  # @param features [Hash<Symbol, Boolean>]
  def set_features(features)
    TransactionChains::Vps::Features.fire(self, build_features(features))
  end

  def deploy_public_key(key)
    TransactionChains::Vps::DeployPublicKey.fire(self, key)
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

  def check_cgroup_version
    return unless cgroup_version != 'cgroup_any' && cgroup_version != node.cgroup_version

    errors.add(
      :cgroup_version,
      "cannot require #{cgroup_version}, #{node.domain_name} uses #{node.cgroup_version}"
    )
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

      raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path unless ds

      parent = ds
      dip = ds.dataset_in_pools.joins(:pool).where(pools: { role: Pool.roles[:hypervisor] }).take

      raise VpsAdmin::API::Exceptions::DatasetDoesNotExist, path unless dip
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
        raise VpsAdmin::API::Exceptions::VpsFeatureConflict.new(f1, f2) if f1.conflict?(f2)
      end
    end

    set
  end
end
