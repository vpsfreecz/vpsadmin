require 'digest'

class NodeKernelConfiguration < ApplicationRecord
  has_many :kernel_configuration_options,
           class_name: 'NodeKernelConfigurationOption',
           dependent: :delete_all,
           inverse_of: :node_kernel_configuration

  validates :digest,
            presence: true,
            uniqueness: true,
            format: { with: /\A[0-9a-f]{64}\z/ }
  validates :content, presence: true
  validate :digest_matches_content

  before_validation :prevent_update!, on: :update
  before_destroy :prevent_destroy!, prepend: true

  def readonly?
    persisted?
  end

  protected

  def digest_matches_content
    return unless digest && content
    return if Digest::SHA256.hexdigest(content) == digest

    errors.add(:digest, 'does not match configuration content')
  end

  def prevent_destroy!
    raise ActiveRecord::ReadOnlyRecord, 'kernel configurations are immutable'
  end

  def prevent_update!
    raise ActiveRecord::ReadOnlyRecord, 'kernel configurations are immutable'
  end
end
