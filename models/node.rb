class Node < ActiveRecord::Base
  self.table_name = 'servers'
  self.primary_key = 'server_id'

  belongs_to :location, :foreign_key => :server_location
  has_many :vpses, :foreign_key => :vps_server
  has_paper_trail

  alias_attribute :name, :server_name
  alias_attribute :addr, :server_ip4

  def location_domain
    "#{name}.#{location.domain}"
  end

  def fqdn
    "#{name}.#{location.fqdn}"
  end
end
