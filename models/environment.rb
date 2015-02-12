class Environment < ActiveRecord::Base
  has_many :nodes
  has_many :environment_config_chains
  has_many :vps_configs, ->{
    order('environment_config_chains.cfg_order ASC')
  }, through: :environment_config_chains
  has_many :environment_user_configs
  has_many :users, through: :environment_user_configs

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

  maintenance_children :nodes

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

  def set_config_chain(configs)
    self.class.transaction do
      # Delete current chain
      vps_configs.delete_all

      # Create new one
      i = 0

      configs.each do |cfg|
        environment_config_chains << EnvironmentConfigChain.new(
          vps_config: cfg,
          cfg_order: i
        )
        i += 1
      end
    end
  end
end
