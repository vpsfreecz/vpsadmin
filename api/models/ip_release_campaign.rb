class IpReleaseCampaign < ApplicationRecord
  class Error < StandardError; end

  MAX_ADDRESSES = 100

  has_many :ip_release_requests
  has_many :ip_release_request_addresses, through: :ip_release_requests
  belongs_to :created_by, class_name: 'User'
  belongs_to :updated_by, class_name: 'User'
  belongs_to :closed_by, class_name: 'User'

  has_paper_trail

  validates :label, presence: true, length: { maximum: 200 }
  validates :deadline, presence: true
  validates :allow_keep, inclusion: { in: [true, false] }

  def self.address_ids!(ids)
    unless ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(Integer) && id > 0 }
      raise Error, 'invalid_addresses'
    end

    ids.uniq.sort
  end

  def self.candidates(filters = {})
    q = IpAddress.joins(:network, :user).where(users: { object_state: %i[active suspended] }).where(network_interface_id: nil).where.not(user_id: nil)
                 .where(networks: { role: :public_access, purpose: %i[any vps] })
                 .where.not(id: IpReleaseRequestAddress.where.not(active_ip_address_id: nil).select(:active_ip_address_id))
                 .where.not(id: ResourceLock.where(resource: 'IpAddress').select(:row_id))
    q = q.where(networks: { ip_version: filters.fetch(:version, 4) })
    q = q.where(user: filters[:user]) if filters[:user]
    q = q.where(network: filters[:network]) if filters[:network]
    if filters[:location]
      q = q.where(network_id: LocationNetwork.where(location: filters[:location]).select(:network_id))
    end
    q
  end

  def self.create_selected!(ids:, actor:, **attrs)
    ids = address_ids!(ids)
    raise Error, 'too_many_addresses' if ids.length > MAX_ADDRESSES

    transaction(requires_new: true) do
      ips = IpAddress.where(id: ids).order(:id).lock.to_a
      raise Error, 'invalid_addresses' unless ips.length == ids.length

      ips.each do |ip|
        unless ip.user && %w[active suspended].include?(ip.user.object_state) && ip.free? && !ip.locked? &&
               ip.network.public_access? && %w[any vps].include?(ip.network.purpose)
          raise Error, 'ineligible_addresses'
        end
      end
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
      ip_release_request_addresses.order(:id).each do |item|
        item.update!(active_ip_address_id: nil)
      end
    end
  end

  def release!(actor:)
    ensure_open!
    ip_release_request_addresses.order(:id).map do |item|
      item.release!(actor:)
    end
  end

  def notify!(event:, actor:)
    with_lock(requires_new: true) do
      ensure_open!
      TransactionChains::IpRelease::Notify.fire(self, event, actor)
    end
  end
end
