class Vps < ActiveRecord::Base
  self.table_name = 'vps'
  self.primary_key = 'vps_id'

  belongs_to :node, :foreign_key => :vps_server
  belongs_to :user, :foreign_key => :m_id
  belongs_to :os_template, :foreign_key => :vps_template
  has_many :ip_addresses
  has_many :transactions, foreign_key: :t_vps

  has_paper_trail

  alias_attribute :hostname, :vps_hostname
  alias_attribute :user_id, :m_id

  validates :m_id, :vps_server, :vps_template, presence: true, numericality: {only_integer: true}
  validates :vps_hostname, presence: true, format: {
      with: /[a-zA-Z\-_\.0-9]{0,255}/,
      message: 'bad format'
  }

  def start
    Transactions::Vps::Start.fire(self)
  end

  def restart
    Transactions::Vps::Restart.fire(self)
  end

  def stop
    Transactions::Vps::Stop.fire(self)
  end
end
