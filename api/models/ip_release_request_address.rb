class IpReleaseRequestAddress < ApplicationRecord
  belongs_to :ip_release_request
  belongs_to :ip_address
  belongs_to :release_chain, class_name: 'TransactionChain'
  belongs_to :kept_by, class_name: 'User'
  belongs_to :exempted_by, class_name: 'User'
  belongs_to :released_by, class_name: 'User'

  has_paper_trail

  validates :keep_reason, presence: true, length: { maximum: 2000 }, if: :kept_at
  validates :exemption_reason, presence: true, length: { maximum: 2000 }, if: :exempted_at

  delegate :ip_release_campaign, to: :ip_release_request

  def original_allocation?(ip = ip_address)
    ip && ip.user_id == ip_release_request.user_id && ip.addr == address &&
      ip.prefix == prefix && ip.network_id == network_id && ip.size == size
  end

  # Never resolve the snapshot through a cached association when deciding
  # whether a later notice or release still concerns the original allocation.
  def exclusion_cause(ip = IpAddress.find_by(id: ip_address_id), owner = ip_release_request.original_user)
    return 'owner_deleted' unless ip_release_request.user_available?(owner)
    return 'address_missing' unless ip
    return 'owner_changed' unless ip.user_id == ip_release_request.user_id
    return 'allocation_changed' unless original_allocation?(ip)

    nil
  end

  def exclude!(reason)
    update!(excluded_at: Time.now, exclusion_reason: reason, active_ip_address_id: nil,
            last_attempt_at: Time.now, last_result: 'changed', last_error: nil)
  end

  def assigned?(ip, lock: false)
    !ip.free? || ip.host_ip_addresses.where.not(order: nil).lock(lock).exists? ||
      IpAddress.where(route_via_id: ip.host_ip_addresses.select(:id)).lock(lock).exists?
  end

  def protection(ip = IpAddress.find_by(id: ip_address_id), owner = ip_release_request.original_user, lock: false)
    return 'released' if released_at
    return 'releasing' if release_in_progress?
    return 'changed' if excluded_at || exclusion_cause(ip, owner)
    return 'assigned' if assigned?(ip, lock:)
    return 'exported' if ip.export_hosts.lock(lock).exists?
    return 'exempted' if exempted_at
    return 'kept' if ip_release_campaign.allow_keep && kept_at

    'eligible'
  end

  def location_label
    network = Network.find_by(id: network_id)
    return unless network
    return network.primary_location.label if network.primary_location

    network.locations.order(:id).pluck(:label).uniq.join(', ').presence
  end

  def public_ipv4?
    network = Network.find_by(id: network_id)
    network && network.public_access? && network.ip_version == 4
  end

  def cleanup_state
    return released_at ? 'done' : nil unless release_chain_id

    release_chain&.state || 'unknown'
  end

  def release_in_progress?
    release_chain_id && %w[staged queued rollbacking fatal].include?(release_chain&.state)
  end

  def last_result
    if self[:last_result] == 'releasing' && !release_in_progress? && !released_at
      'failed'
    else
      self[:last_result]
    end
  end

  def exempt!(reason:, actor:)
    ip_release_campaign.with_lock(requires_new: true) do
      ip_release_campaign.ensure_open!
      reload(lock: true)
      raise IpReleaseCampaign::Error, 'already_released' if released_at || release_in_progress?
      raise IpReleaseCampaign::Error, 'owner_changed' if excluded_at || exclusion_cause

      update!(exemption_reason: reason&.strip, exempted_at: reason.nil? ? nil : Time.now,
              exempted_by: reason.nil? ? nil : actor)
    end
  end

  def release!(actor:)
    self.class.transaction(requires_new: true) do
      campaign = ip_release_campaign
      campaign.lock!
      campaign.ensure_open!
      reload(lock: true)
      ip_release_request.ip_release_campaign = campaign
      result = protection
      if !excluded_at && %w[eligible changed].include?(result)
        chain, = TransactionChains::IpRelease::Release.fire(self, actor)
        update!(release_chain: chain)
      else
        update!(last_attempt_at: Time.now, last_result: result, last_error: nil)
      end
    end
    reload
  rescue ResourceLocked, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound,
         ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
         VpsAdmin::API::Exceptions::IpAddressInvalidLocation,
         VpsAdmin::API::Exceptions::ClusterResourceAllocationError => e
    ip_release_campaign.with_lock(requires_new: true) do
      reload(lock: true)
      update!(last_attempt_at: Time.now, last_result: 'failed', last_error: e.message) unless released_at || release_in_progress?
    end
    self
  end
end
