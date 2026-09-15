class IpReleaseCampaign < ApplicationRecord
  class Error < StandardError; end

  has_many :ip_release_requests
  has_many :ip_release_request_addresses, through: :ip_release_requests
  belongs_to :created_by, class_name: 'User'
  belongs_to :updated_by, class_name: 'User'
  belongs_to :closed_by, class_name: 'User'

  has_paper_trail

  validates :deadline, presence: true
  validates :allow_keep, inclusion: { in: [true, false] }

  def self.address_ids!(ids)
    unless ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(Integer) && id > 0 }
      raise Error, 'invalid_addresses'
    end

    ids.uniq.sort
  end

  # Shared by preview and creation. Export grants and host-level assignments
  # also make an allocation in use, even without a parent interface assignment.
  def self.eligible_allocations
    assigned_hosts = HostIpAddress.where.not(order: nil).select(:ip_address_id)
    routed_hosts = HostIpAddress.where(id: IpAddress.where.not(route_via_id: nil).select(:route_via_id))
    IpAddress.joins(:network, :user)
             .where(users: { object_state: %i[active suspended] }, network_interface_id: nil,
                    networks: { purpose: %i[any vps] })
             .where.not(id: assigned_hosts)
             .where.not(id: routed_hosts.select(:ip_address_id))
             .where.not(id: ExportHost.where.not(ip_address_id: nil).select(:ip_address_id))
             .where.not(id: ResourceLock.where(resource: 'IpAddress').select(:row_id))
  end

  def self.candidates(filters = {})
    versions = filter_ids!(filters.fetch(:versions, [4]))
    networks = filter_ids!(filters.fetch(:networks, []))
    locations = filter_ids!(filters.fetch(:locations, []))
    raise Error, 'invalid_filters' unless versions.any? && (versions - [4, 6]).empty?

    access = filters.fetch(:access, 'public_access')
    raise Error, 'invalid_filters' unless %w[public_access private_access all].include?(access)

    q = eligible_allocations
        .where.not(id: IpReleaseRequestAddress.where.not(active_ip_address_id: nil).select(:active_ip_address_id))
        .where(networks: { ip_version: versions })
    q = q.where(networks: { role: access }) unless access == 'all'
    q = q.where(user: filters[:user]) if filters[:user]
    q = q.where(network_id: networks) if networks.any?
    q = q.where(network_id: LocationNetwork.where(location_id: locations).select(:network_id)) if locations.any?
    q
  end

  def self.filter_ids!(values)
    values = values.empty? ? [] : values.split(',', -1).map(&:strip) if values.is_a?(String)

    unless values.is_a?(Array) && values.all? { |v| (v.is_a?(Integer) && v > 0) || (v.is_a?(String) && /\A[1-9][0-9]*\z/.match?(v)) }
      raise Error, 'invalid_filters'
    end

    values.map(&:to_i).uniq
  end

  def self.create_selected!(ids:, actor:, **attrs)
    ids = address_ids!(ids)

    transaction(requires_new: true) do
      ips = IpAddress.where(id: ids).order(:id).lock.to_a
      raise Error, 'invalid_addresses' unless ips.length == ids.length

      raise Error, 'ineligible_addresses' unless eligible_allocations.where(id: ids).count == ids.length

      campaign = create!(**attrs, created_by: actor, updated_by: actor)
      ips.group_by(&:user_id).each do |user_id, addresses|
        request = campaign.ip_release_requests.create!(user_id:)
        addresses.each do |ip|
          request.ip_release_request_addresses.create!(
            ip_address: ip, active_ip_address_id: ip.id, network_id: ip.network_id,
            address: ip.addr, prefix: ip.prefix, size: ip.size
          )
        end
      end
      campaign
    end
  rescue ActiveRecord::RecordNotUnique
    raise Error, 'duplicate_addresses'
  end

  def ensure_open!
    raise Error, 'closed' if closed_at
  end

  def edit!(attrs, actor:)
    with_lock(requires_new: true) do
      ensure_open!
      update!(attrs.merge(updated_by: actor))
    end
  end

  def close!(actor:)
    with_lock(requires_new: true) do
      ensure_open!
      update!(closed_at: Time.now, closed_by: actor, updated_by: actor)
      ip_release_request_addresses.find_each(batch_size: 100) do |item|
        item.update!(active_ip_address_id: nil)
      end
    end
  end

  def exempt!(ids:, reason:, actor:)
    ids = self.class.address_ids!(ids)

    with_lock(requires_new: true) do
      ensure_open!
      items = ip_release_request_addresses.where(id: ids).order(:id).lock.to_a
      raise Error, 'invalid_addresses' unless items.length == ids.length

      items.each do |item|
        raise Error, 'already_released' if item.released_at || item.release_in_progress?
        raise Error, 'owner_changed' if item.excluded_at || item.exclusion_cause
      end

      now = Time.now
      items.each do |item|
        item.update!(exemption_reason: reason&.strip, exempted_at: reason.nil? ? nil : now,
                     exempted_by: reason.nil? ? nil : actor)
      end
      items
    end
  end

  def release!(actor:)
    ensure_open!
    ip_release_request_addresses.find_each(batch_size: 100).map do |item|
      item.release!(actor:)
    end
  end

  def notification_targets(event)
    return enum_for(__method__, event) unless block_given?

    ip_release_requests.find_each(batch_size: 100) do |request|
      next unless request.notice_available?(event)

      addresses = request.eligible_addresses
      yield request, addresses if addresses.any?
    end
  end

  def can_send_initial_notices
    !closed_at && notification_targets('requested').any?
  end

  def can_send_reminders
    !closed_at && notification_targets('reminder').any?
  end

  def can_release
    !closed_at && ip_release_request_addresses.find_each(batch_size: 100).any? do |item|
      !item.excluded_at && %w[eligible changed].include?(item.protection)
    end
  end

  def notify!(event:, actor:)
    with_lock(requires_new: true) do
      ensure_open!
      TransactionChains::IpRelease::Notify.fire(self, event, actor)
    end
  end
end
