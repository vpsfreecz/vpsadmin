class Location < ActiveRecord::Base
  self.primary_key = 'location_id'

  belongs_to :environment
  has_many :nodes, :foreign_key => :server_location
  has_many :ip_addresses, :foreign_key => :ip_location
  has_paper_trail

  alias_attribute :label, :location_label

  validates :location_label, :location_has_ipv6, :location_vps_onboot,
            :environment_id, :domain, presence: true
  validates :environment_id, numericality: {only_integer: true}
  validates :domain, format: {
      with: /[[0-9a-zA-Z\-\.]{3,255}]/,
      message: 'invalid format'
  }
  validates :location_remote_console_server, allow_blank: true, format: {
      with: /\A(https?:\/\/.+)?\Z/,
      message: 'invalid format'
  }

  def fqdn
    "#{domain}.#{environment.fqdn}"
  end
end
