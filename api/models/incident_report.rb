class IncidentReport < ActiveRecord::Base
  belongs_to :user
  belongs_to :vps
  belongs_to :ip_address_assignment
  belongs_to :filed_by, class_name: 'User'
  belongs_to :mailbox

  validates :subject, :text, presence: true, allow_blank: false

  def ip_address
    ip_address_assignment && ip_address_assignment.ip_address
  end

  def raw_user_id
    user_id
  end

  def raw_vps_id
    vps_id
  end
end
