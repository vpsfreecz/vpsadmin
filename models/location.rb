class Location < ActiveRecord::Base
  self.primary_key = 'location_id'

  has_many :nodes, :foreign_key => :server_location
  has_many :networks
  has_many :dns_resolvers, foreign_key: :dns_location
  has_paper_trail ignore: %i(maintenance_lock maintenance_lock_reason)

  alias_attribute :label, :location_label
  alias_attribute :has_ipv6, :location_has_ipv6

  validates :location_label, :location_vps_onboot,
            :domain, presence: true
  validates :location_has_ipv6, inclusion: { in: [true, false] }
  validates :domain, format: {
      with: /[[0-9a-zA-Z\-\.]{3,255}]/,
      message: 'invalid format'
  }
  validates :location_remote_console_server, allow_blank: true, format: {
      with: /\A(https?:\/\/.+)?\Z/,
      message: 'invalid format'
  }

  include VpsAdmin::API::Maintainable::Model

  maintenance_parents do
    MaintenanceLock.find_by(
        class_name: 'Cluster',
        row_id: nil,
        active: true
    )
  end

  maintenance_children :nodes

  def fqdn
    domain
  end
end
