class IpReleaseRequest < ApplicationRecord
  belongs_to :ip_release_campaign
  belongs_to :user
  has_many :ip_release_request_notices
  has_many :ip_release_request_addresses

  has_paper_trail

  delegate :label, :deadline, :allow_keep, :closed_at, to: :ip_release_campaign

  def original_user_id
    user_id
  end

  def original_user
    User.unscoped.find_by(id: user_id)
  end

  def user_available?(owner = original_user)
    owner && %w[active suspended].include?(owner.object_state)
  end

  def user_login
    owner = original_user
    owner.login if user_available?(owner)
  end

  def last_notice
    ip_release_request_notices.order(:id).last
  end

  def notified_at
    last_notice&.created_at
  end

  def mail_log
    last_notice&.mail_log
  end

  def mail_log_id
    last_notice&.mail_log_id
  end

  def keep!(ids:, reason:, actor:)
    ids = IpReleaseCampaign.address_ids!(ids)
    ip_release_campaign.with_lock(requires_new: true) do
      ip_release_campaign.ensure_open!
      raise IpReleaseCampaign::Error, 'access_denied' unless user_id == actor.id
      raise IpReleaseCampaign::Error, 'keep_disabled' unless allow_keep

      items = ip_release_request_addresses.where(id: ids).order(:id).to_a
      raise IpReleaseCampaign::Error, 'invalid_addresses' unless items.length == ids.length
      if items.any? { |item| item.released_at || item.release_in_progress? }
        raise IpReleaseCampaign::Error, 'already_released'
      end

      items.each do |item|
        raise IpReleaseCampaign::Error, 'owner_changed' if item.excluded_at || item.exclusion_cause

        item.update!(keep_reason: reason.to_s.strip, kept_at: Time.now, kept_by: actor)
      end
    end
  end
end
