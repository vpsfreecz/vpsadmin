require_relative 'lockable'

class VpsConfig < ActiveRecord::Base
  has_many :vps_has_configs
  has_many :vpses, through: :vps_has_configs
  has_many :environment_config_chains
  has_many :environments, through: :environment_config_chains

  has_paper_trail

  validates :name, :label, :config, presence: true

  include Lockable

  def create!
    TransactionChains::VpsConfig::Create.fire(self)
  end

  def update!(attrs)
    assign_attributes(attrs)
    fail ActiveRecord::RecordInvalid unless valid?
    TransactionChains::VpsConfig::Update.fire(self)
  end

  def destroy
    TransactionChains::VpsConfig::Delete.fire(self)
  end
end
