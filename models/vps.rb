class Vps < ActiveRecord::Base
  self.table_name = 'vps'
  self.primary_key = 'vps_id'

  belongs_to :node, :foreign_key => :vps_server
  belongs_to :user, :foreign_key => :m_id
  belongs_to :os_template, :foreign_key => :vps_template
  has_many :ip_addresses
  has_many :transactions, foreign_key: :t_vps

  has_many :vps_has_config, -> { order '`order`' }
  has_many :vps_configs, through: :vps_has_config

  has_paper_trail

  alias_attribute :veid, :vps_id
  alias_attribute :hostname, :vps_hostname
  alias_attribute :user_id, :m_id

  validates :m_id, :vps_server, :vps_template, presence: true, numericality: {only_integer: true}
  validates :vps_hostname, presence: true, format: {
      with: /[a-zA-Z\-_\.0-9]{0,255}/,
      message: 'bad format'
  }

  def create
    self.vps_backup_export = 0
    self.vps_backup_exclude = ''
    self.vps_config = ''

    if save
      set_config_chain(VpsConfig.default_config_chain(node.location))

      Transactions::Vps::New.fire(self)

    else
      false
    end
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
end
