class Environment < ActiveRecord::Base
  has_many :locations
  has_paper_trail

  validates :label, :domain, presence: true
  validates :domain, format: {
    with: /[0-9a-zA-Z\-\.]{3,255}/,
    message: 'invalid format'
  }

  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model

  maintenance_parent do
    MaintenanceLock.find_by(
        class_name: 'Cluster',
        row_id: nil,
        active: true
    )
  end

  maintenance_children :locations

  def fqdn
    domain
  end

  def vps_count
    locations.all.inject(0) do |sum, loc|
      loc.nodes.all.each do |node|
        sum += node.vpses.count
      end

      sum
    end
  end
end
