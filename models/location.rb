class Location < ActiveRecord::Base
  self.primary_key = 'location_id'

  belongs_to :environment
  has_many :nodes, :foreign_key => :server_location
  has_many :ip_addresses, :foreign_key => :ip_location
  has_paper_trail

  alias_attribute :label, :location_label

  def fqdn
    "#{domain}.#{environment.fqdn}"
  end
end
