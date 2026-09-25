class StorageFreezeTransition < ApplicationRecord
  belongs_to :storage_freeze_control

  enum :prior_mode, %i[read_write read_only], prefix: :prior
  enum :new_mode, %i[read_write read_only], prefix: :new

  validates :prior_epoch, :new_epoch,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :actor_user_id, :actor_user_session_id,
            numericality: { only_integer: true, greater_than: 0 }
  validates :actor_user_login, presence: true, length: { maximum: 128 }
  validates :reason, presence: true, length: { maximum: 255 }
  validates :created_at, presence: true
  validate :mode_and_epoch_changed
  validate :safe_actor_text

  def readonly?
    persisted?
  end

  private

  def mode_and_epoch_changed
    errors.add(:new_mode, 'must differ from prior mode') if prior_mode == new_mode
    return if prior_epoch.nil? || new_epoch.nil?

    errors.add(:new_epoch, 'must follow prior epoch') unless new_epoch == prior_epoch + 1
  end

  def safe_actor_text
    errors.add(:reason, 'contains a control character') if reason.to_s.match?(/[[:cntrl:]]/)
    errors.add(:actor_user_login, 'contains a control character') if actor_user_login.to_s.match?(/[[:cntrl:]]/)
    errors.add(:actor_user_login, 'is required') if actor_user_login.to_s.strip.empty?
  end
end
