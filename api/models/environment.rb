require 'vpsadmin/api/maintainable'

class Environment < ActiveRecord::Base
  has_many :locations
  has_many :environment_config_chains
  has_many :environment_user_configs
  has_many :users, through: :environment_user_configs
  has_many :environment_dataset_plans
  has_many :default_object_cluster_resources
  has_many :default_user_cluster_resource_packages
  has_many :charged_ip_addresses,
           class_name: 'IpAddress',
           foreign_key: 'charged_environment_id'

  has_paper_trail ignore: %i[maintenance_lock maintenance_lock_reason]

  validates :label, :domain, presence: true
  validates :domain, format: {
    with: /[0-9a-zA-Z\-.]{3,255}/,
    message: 'invalid format'
  }

  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Maintainable::Model

  maintenance_parents do
    MaintenanceLock.find_by(
      class_name: 'Cluster',
      row_id: nil,
      active: true
    )
  end

  maintenance_children :locations

  def update!(attrs)
    assign_attributes(attrs)

    self.class.transaction do
      environment_user_configs.where(default: true).update_all(
        can_create_vps: can_create_vps,
        can_destroy_vps: can_destroy_vps,
        vps_lifetime: vps_lifetime,
        max_vps_count: max_vps_count
      )

      save!
    end

    self
  end

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
