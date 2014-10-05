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

  def create(add_ips)
    self.vps_backup_export = 0
    self.vps_backup_exclude = ''
    self.vps_config = ''

    self.dns_resolver_id ||= DnsResolver.pick_suitable_resolver_for_vps(self).id

    if save
      TransactionChains::VpsCreate.fire(self, add_ips)
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
      TransactionChains::VpsDestroy.fire(self)
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
          to_change[attr] = send(attr[0..-4])
        else
          to_change[attr] = send(attr)
        end

        send("#{attr}=", changed_attributes[attr])
      end
    end

    unless to_change.empty?
      TransactionChains::VpsUpdate.fire(self, to_change)
    end

    (changed? && save) || true
  end

  def start
    TransactionChains::VpsStart.fire(self)
  end

  def restart
    TransactionChains::VpsRestart.fire(self)
  end

  def stop
    TransactionChains::VpsStop.fire(self)
  end

  def applyconfig
    # Transactions::Vps::ApplyConfig.fire(self)
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

      TransactionChains::VpsAddIp.fire(self, [ip])
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

      TransactionChains::VpsDelIp.fire(self, [ip])
    end
  end

  def delete_ips(v=nil)
    ::IpAddress.transaction do
      if v
        ips = ip_addresses.where(ip_v: v)
      else
        ips = ip_addresses.all
      end

      TransactionChains::VpsDelIp.fire(self, ips)
    end
  end

  def passwd
    pass = generate_password

    TransactionChains::VpsPasswd.fire(self, pass)

    pass
  end

  def reinstall(template)
    TransactionChains::VpsReinstall.fire(self, template)
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
end
