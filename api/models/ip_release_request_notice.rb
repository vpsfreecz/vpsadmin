class IpReleaseRequestNotice < ApplicationRecord
  belongs_to :ip_release_request
  belongs_to :mail_log
  belongs_to :created_by, class_name: 'User'

  has_paper_trail

  validates :event, inclusion: { in: %w[requested reminder] }

  def created_by_login
    User.unscoped.find_by(id: created_by_id)&.login
  end

  delegate :subject, to: :mail_log
end
