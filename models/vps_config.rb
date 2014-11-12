class VpsConfig < ActiveRecord::Base
  self.table_name = 'config'

  has_many :vps_has_config, foreign_key: :config_id
  has_many :vpses, through: :vps_has_config
  has_many :environment_config_chains
  has_many :environments, through: :environment_config_chains

  has_paper_trail

  validates :name, :label, :config, presence: true

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
