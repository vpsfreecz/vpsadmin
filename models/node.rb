class Node < ActiveRecord::Base
  self.table_name = 'servers'
  self.primary_key = 'server_id'

  belongs_to :environment
  belongs_to :location, :foreign_key => :server_location
  has_many :vpses, :foreign_key => :vps_server
  has_many :transactions, foreign_key: :t_server
  has_many :storage_roots
  has_many :pools
  has_many :vps_mounts, foreign_key: :server_id
  has_many :port_reservations
  has_many :node_statuses
  belongs_to :node_status

  has_paper_trail ignore: %i(maintenance_lock maintenance_lock_reason)

  alias_attribute :name, :server_name
  alias_attribute :addr, :server_ip4
  alias_attribute :vps_max, :max_vps

  validates :server_name, :server_type, :server_location, :server_ip4, presence: true
  validates :server_location, numericality: {only_integer: true}
  validates :server_name, format: {
      with: /\A[a-zA-Z0-9\.\-_]+\Z/,
      message: 'invalid format'
  }
  validates :server_type, inclusion: {
      in: %w(node storage mailer),
      message: '%{value} is not a valid node role'
  }
  validates :server_ip4, format: {
      with: /\A\d+\.\d+\.\d+\.\d+\Z/,
      message: 'not a valid IPv4 address'
  }
  validates :max_vps, presence: true, numericality: {
      only_integer: true,
      greater_than: 0
  }, if: :hypervisor?
  validates :ve_private, presence: true, if: :hypervisor?

  after_update :shaper_changed, if: :shaper_changed?

  include VpsAdmin::API::Maintainable::Model

  maintenance_parents :location, :environment
  maintenance_children :vpses

  include Lockable

  def self.register!(attrs)
    opts = {
        maintenance: attrs.delete(:maintenance)
    }
    n = new(attrs)

    TransactionChains::Node::Register.fire(n, opts)
  end

  def location_domain
    "#{name}.#{location.domain}"
  end

  def fqdn
    "#{name}.#{location.domain}.#{environment.domain}"
  end

  def self.pick_by_env(env, location = nil, except = nil)
    q = self.joins('
          LEFT JOIN vps ON vps.vps_server = servers.server_id
          LEFT JOIN vps_status st ON st.vps_id = vps.vps_id
          INNER JOIN locations ON locations.location_id = servers.server_location
        ').where('
          (st.vps_up = 1 OR st.vps_up IS NULL)
          AND servers.max_vps > 0
          AND servers.maintenance_lock = 0
          AND servers.environment_id = ?
        ', env.id)

    if location
      q = q.where('locations.location_id = ?', location.id)
    end

    q = q.where('servers.server_id != ?', except.id) if except

    n = q.group('servers.server_id')
     .order('COUNT(st.vps_up) / max_vps ASC')
     .take

    return n if n
    
    q = self.joins(
        'LEFT JOIN vps ON vps.vps_server = servers.server_id'
    ).where(
        'max_vps > 0'
    ).where(
        maintenance_lock: 0,
        environment: env
    )

    if location
      q = q.where('server_location = ?', location.id)
    end
    
    q = q.where('servers.server_id != ?', except.id) if except

    q.group('servers.server_id').order('COUNT(vps_id) / max_vps ASC').take
  end

  def self.pick_by_location(loc)
    n = self.joins('
        LEFT JOIN vps ON vps.vps_server = servers.server_id
        LEFT JOIN vps_status st ON st.vps_id = vps.vps_id
        INNER JOIN locations l ON server_location = location_id
      ').where('
        (st.vps_up = 1 OR st.vps_up IS NULL)
        AND servers.max_vps > 0
        AND servers.maintenance_lock = 0
        AND location_id = ?
      ', loc.id).group('server_id')
      .order('COUNT(st.vps_up) / max_vps ASC')
      .take

    return n if n

    self.joins(
        'LEFT JOIN vps ON vps.vps_server = servers.server_id'
    ).where(
        'max_vps > 0'
    ).where(
        maintenance_lock: 0,
        server_location: loc.id
    ).group('servers.server_id').order('COUNT(vps_id) / max_vps ASC').take
  end

  def self.first_available
    return self.joins(:node_status).order('servers_status.created_at DESC').take!
  end

  def status
    (node_status && ((Time.now.utc.to_i - node_status.created_at.to_i) <= 150)) || false
  end

  def last_report
    node_status && node_status.created_at
  end

  def domain_name
    "#{name}.#{location.domain}"
  end

  def vps_running
    vpses.joins(:vps_status).where(vps_statuses: {is_running: true}).count
  end

  def vps_stopped
    vpses.joins(:vps_status).where(vps_statuses: {is_running: false}).count
  end

  def vps_deleted
    vpses.unscoped.where(
        node: self,
        object_state: ::Vps.object_states['soft_delete']
    ).count
  end

  def vps_total
    return @vps_total if @vps_total
    @vps_total = vpses.count
  end

  def vps_free
    max_vps && (max_vps - vps_total)
  end
  
  %i(uptime process_count cpu_user cpu_nice cpu_system cpu_idle cpu_iowait
     cpu_irq cpu_softirq cpu_guest loadavg used_memory used_swap arc_c_max arc_c
     arc_size arc_hitpercent kernel vpsadmind_version
  ).each do |attr|
    define_method(attr) do
      node_status && node_status.send(attr)
    end
  end

  def daemon_version
    node_status && node_status.vpsadmind_version
  end

  def kernel_version
    node_status && node_status.kernel
  end

  def hypervisor?
    server_type == 'node'
  end

  protected
  def shaper_changed?
    max_tx_changed? || max_rx_changed?
  end

  def shaper_changed
    TransactionChains::Node::ShaperRootChange.fire(self) unless net_interface.nil?
  end
end
