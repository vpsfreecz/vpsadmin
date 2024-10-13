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

class Vps < ApplicationRecord
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
  has_many :oom_report_counters, dependent: :delete_all
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

  before_create :set_lifetime

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

  def pool
    dataset_in_pool.pool
  end

  %i[is_running in_rescue_mode uptime process_count cpu_user cpu_nice cpu_system
     cpu_idle cpu_iowait cpu_irq cpu_softirq loadavg1 loadavg5 loadavg15
     used_memory used_swap].each do |attr|
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

  private

  def set_lifetime
    lifetime = user.env_config(
      node.location.environment,
      :vps_lifetime
    )

    self.expiration_date = Time.now + lifetime if lifetime != 0
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
end
