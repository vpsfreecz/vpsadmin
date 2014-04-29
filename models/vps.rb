class Vps < ActiveRecord::Base
  self.table_name = 'vps'
  self.primary_key = 'vps_id'

  belongs_to :node, :foreign_key => :vps_server
  belongs_to :user, :foreign_key => :m_id
  belongs_to :os_template, :foreign_key => :vps_template
  has_many :ip_addresses

  has_paper_trail

  alias_attribute :hostname, :vps_hostname

  validates :hostname, presence: true, format: {
      with: /[a-zA-Z\-_\.0-9]{0,255}/,
      message: 'bad format'
  }
end
