class IpAddress < ActiveRecord::Base
  self.table_name = 'vps_ip'
  self.primary_key = 'ip_id'

  belongs_to :location, :foreign_key => :ip_location
  belongs_to :vps, :foreign_key => :vps_id
  belongs_to :user
  has_paper_trail

  validates :ip_v, inclusion: {
      in: [4, 6],
      message: '%{value} is not a valid IP version'
  }
  validate :check_address
  validates :ip_addr, uniqueness: true

  alias_attribute :addr, :ip_addr
  alias_attribute :version, :ip_v

  include Lockable

  def self.register(addr, params)
    ip = nil

    self.transaction do
      class_id = nil

      begin
        class_id = self.select('ip1.class_id+1 AS first_id')
            .from('vps_ip ip1')
            .joins('LEFT JOIN vps_ip ip2 ON ip2.class_id = ip1.class_id + 1')
            .where('ip2.class_id IS NULL')
            .order('ip1.class_id')
            .take!.first_id

      rescue ActiveRecord::RecordNotFound
        class_id = 1
      end

      ip = self.new(
          ip_addr: addr.to_s,
          ip_v: addr.ipv4? ? 4 : 6,
          location: params[:location],
          class_id: class_id,
          user: params[:user]
      )

      ip.max_tx = params[:max_tx] if params[:max_tx]
      ip.max_rx = params[:max_rx] if params[:max_rx]
      ip.save!
    end

    ip
  end

  def free?
    vps_id.nil? || vps_id == 0
  end

  # Return first free and unlocked IP address version +v+ from +location+.
  def self.pick_addr!(user, location, v)
    self.select('vps_ip.*')
      .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = vps_ip.ip_id")
      .where(ip_v: v, location: location)
      .where('vps_id IS NULL')
      .where('(vps_ip.user_id = ? OR vps_ip.user_id IS NULL)', user.id)
      .where('rl.id IS NULL')
      .order('vps_ip.user_id DESC, ip_id').take!
  end

  def set_shaper(tx, rx)
    if vps_id > 0
      TransactionChains::Vps::ShaperChange.fire(
          self,
          tx || self.max_tx,
          rx || self.max_rx
      )
    else
      self.max_tx = tx
      self.max_rx = rx
      save!
    end
  end

  def check_address
    a = ::IPAddress.parse(ip_addr)

    if (a.ipv4? && ip_v != 4) || (a.ipv6? && ip_v != 6)
      errors.add(:ip_addr, 'IP version does not match the address')

    elsif a.network? && a.prefix != (a.ipv4? ? 32 : 128)
      errors.add(:ip_addr, 'not a host address')
    end

  rescue ArgumentError => e
    errors.add(:ip_addr, e.message)
  end
end
