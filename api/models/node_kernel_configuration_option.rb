class NodeKernelConfigurationOption < ApplicationRecord
  belongs_to :node_kernel_configuration,
             inverse_of: :kernel_configuration_options

  validates :name,
            presence: true,
            format: { with: /\ACONFIG_[A-Z0-9_]+\z/ },
            uniqueness: { scope: :node_kernel_configuration_id }

  before_validation :prevent_update!, on: :update
  before_destroy :prevent_destroy!

  def readonly?
    persisted?
  end

  protected

  def prevent_destroy!
    raise ActiveRecord::ReadOnlyRecord, 'kernel configuration options are immutable'
  end

  def prevent_update!
    raise ActiveRecord::ReadOnlyRecord, 'kernel configuration options are immutable'
  end
end
