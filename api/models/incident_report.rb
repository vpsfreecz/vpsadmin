class IncidentReport < ApplicationRecord
  belongs_to :user
  belongs_to :vps
  belongs_to :ip_address_assignment
  belongs_to :filed_by, class_name: 'User'
  belongs_to :mailbox

  validates :subject, :text, presence: true, allow_blank: false

  before_create :set_reported_at

  def ip_address
    ip_address_assignment && ip_address_assignment.ip_address
  end

  def raw_user_id
    user_id
  end

  def raw_vps_id
    vps_id
  end

  protected

  def set_reported_at
    self.reported_at ||= Time.now
  end
end
