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

  after_update :hostname_changed, if: :vps_hostname_changed?

  def create
    self.vps_backup_export = 0
    self.vps_backup_exclude = ''
    self.vps_config = ''

    p attributes

    if save
      set_config_chain(VpsConfig.default_config_chain(node.location))

      last_id = Transactions::Vps::New.fire(self)

      mapping, last_id = StorageExport.create_default_exports(self, depend: last_id)
      create_default_mounts(mapping)

      Transactions::Vps::Mounts.fire_chained(last_id, self, false)
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

  def destroy
    delete_mounts
    delete_ips
    Transactions::Vps::Destroy.fire(self)
    super
  end

  def start
    Transactions::Vps::Start.fire(self)
  end

  def restart
    Transactions::Vps::Restart.fire(self)
  end

  def stop
    Transactions::Vps::Stop.fire(self)
  end

  def applyconfig
    Transactions::Vps::ApplyConfig.fire(self)
  end

  def set_config_chain(chain)
    i = 0

    chain.each do |c|
      VpsHasConfig.new(vps_id: veid, config_id: c, order: i).save
      i += 1
    end
  end

  def add_ip(ip)
    ip_addresses << ip

    Transactions::Vps::IpAdd.fire(self, ip)
  end

  def delete_ip(ip)
    ip_addresses.delete(ip)

    Transactions::Vps::IpDel.fire(self, ip)
  end

  def delete_ips(v=nil)
    if v
      ips = ip_addresses.where(ip_v: v)
    else
      ips = ip_addresses.all
    end

    ips.each do |ip|
      delete_ip(ip)
    end
  end

  def passwd
    pass = generate_password

    Transactions::Vps::Passwd.fire(self, pass)

    pass
  end

  def reinstall
    Transactions::Vps::ReinstallChain.fire(self)
  end

  private
  def generate_password
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
    (0..20).map { chars.sample }.join
  end

  def hostname_changed
    Transactions::Vps::Hostname.fire(self)
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
