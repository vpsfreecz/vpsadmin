class WebuiUserSetting < ApplicationRecord
  MAX_SETTINGS_PER_USER = 64
  MAX_VALUE_BYTES = 8 * 1024
  MAX_TOTAL_VALUE_BYTES = 64 * 1024
  ALLOWED_NAMESPACES = %w[forms tips ui].freeze
  KEY_FORMAT = /\A[a-z0-9_.-]+\z/

  belongs_to :user

  serialize :value, coder: JSON

  validates :user, :namespace, :key, presence: true
  validates :namespace, inclusion: { in: ALLOWED_NAMESPACES }
  validates :namespace, :key, format: { with: KEY_FORMAT }
  validates :namespace, length: { maximum: 75 }
  validates :key, length: { maximum: 100 }
  validates :key, uniqueness: { scope: %i[user_id namespace] }
  validate :value_is_present
  validate :value_size_is_within_limit
  validate :user_quota_is_within_limit

  def self.set!(user:, namespace:, key:, value:)
    transaction do
      ::User.lock.find(user.id)

      setting = find_or_initialize_by(
        user_id: user.id,
        namespace: namespace,
        key: key
      )
      setting.value = value
      setting.save!
      setting
    end
  end

  def serialized_value
    JSON.dump(value)
  end

  def serialized_value_bytes
    serialized_value.bytesize
  end

  protected

  def value_is_present
    errors.add(:value, 'must not be null') if value.nil?
  end

  def value_size_is_within_limit
    return if value.nil?

    if serialized_value_bytes > MAX_VALUE_BYTES
      errors.add(
        :value,
        "is too large (maximum #{MAX_VALUE_BYTES} bytes)"
      )
    end
  rescue JSON::GeneratorError, TypeError
    errors.add(:value, 'must be JSON-serializable')
  end

  def user_quota_is_within_limit
    return if user_id.nil? || value.nil? || errors[:value].any?

    settings = self.class.where(user_id: user_id)
    settings = settings.where.not(id: id) if persisted?

    if new_record? && settings.count >= MAX_SETTINGS_PER_USER
      errors.add(
        :base,
        "cannot store more than #{MAX_SETTINGS_PER_USER} web UI settings"
      )
    end

    total_size = settings.to_a.sum(&:serialized_value_bytes) + serialized_value_bytes
    return unless total_size > MAX_TOTAL_VALUE_BYTES

    errors.add(
      :base,
      "web UI settings exceed #{MAX_TOTAL_VALUE_BYTES} bytes"
    )
  end
end
