require 'vpsadmin/api/maintainable'

class Location < ActiveRecord::Base
  belongs_to :environment
  has_many :nodes
  has_many :location_networks
  has_many :networks, through: :location_networks
  has_many :dns_resolvers
  has_paper_trail ignore: %i(maintenance_lock maintenance_lock_reason)

  validates :label, :domain, presence: true
  validates :has_ipv6, inclusion: { in: [true, false] }
  validates :domain, format: {
    with: /[[0-9a-zA-Z\-\.]{3,255}]/,
    message: 'invalid format'
  }
  validates :remote_console_server, allow_blank: true, format: {
    with: /\A(https?:\/\/.+)?\Z/,
    message: 'invalid format'
  }

  include VpsAdmin::API::Maintainable::Model

  maintenance_parents :environment
  maintenance_children :nodes

  def fqdn
    domain
  end

  def shares_any_networks_with_primary?(location, userpick: nil)
    q = location_networks
      .select('location_networks.location_id')
      .joins('INNER JOIN location_networks ln2')
      .where('location_networks.location_id != ln2.location_id')
      .where('location_networks.network_id = ln2.network_id')
      .where('ln2.location_id = ?', location.id)
      .where('ln2.primary = 1')

    if !userpick.nil?
      q = q.where('ln2.userpick = ?', userpick)
    end

    q.count > 0
  end

  def any_shared_networks_with_primary(location, userpick: nil)
    net_ids = location_networks
      .select('location_networks.network_id')
      .joins('INNER JOIN location_networks ln2')
      .where('location_networks.location_id != ln2.location_id')
      .where('location_networks.network_id = ln2.network_id')
      .where('ln2.location_id = ?', location.id)
      .where('ln2.primary = 1')

    if !userpick.nil?
      net_ids = net_ids.where('ln2.userpick = ?', userpick)
    end

    ::Network.where(id: net_ids.pluck(:network_id))
  end
end
