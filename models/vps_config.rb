class VpsConfig < ActiveRecord::Base
  self.table_name = 'config'

  has_many :vps_has_config, foreign_key: :config_id
  has_many :vpses, through: :vps_has_config

  has_paper_trail

  validates :name, :label, :config, presence: true

  def self.default_config_chain(location)
    if location.location_type == 'production'
      chain = SysConfig.get('default_config_chain')

    else
      chain = SysConfig.get('playground_default_config_chain')
    end

    chain ||= []

    chain.map! do |v|
      v.to_i
    end
  end

  def create!
    TransactionChains::VpsConfig::Create.fire(self)
  end

  def update!(attrs)
    assign_attributes(attrs)
    fail ActiveRecord::RecordInvalid unless valid?
    TransactionChains::VpsConfig::Create.fire(self)
    save!
  end

  def destroy
    TransactionChains::VpsConfig::Delete.fire(self)
    super
  end
end
