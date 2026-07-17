class NodeSystemState < ApplicationRecord
  belongs_to :node

  enum :cgroup_version, %i[cgroup_invalid cgroup_v1 cgroup_v2]

  scope :current, -> { where(current: true) }

  validates :first_observed_at, :last_observed_at, presence: true
  validates :cpus, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :total_memory,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :total_swap,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validate :last_observation_is_not_before_first

  protected

  def last_observation_is_not_before_first
    return unless first_observed_at && last_observed_at
    return if last_observed_at >= first_observed_at

    errors.add(:last_observed_at, 'must not be before the first observation')
  end
end
