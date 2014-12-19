class IpAddress < ActiveRecord::Base
  self.table_name = 'vps_ip'
  self.primary_key = 'ip_id'

  belongs_to :location, :foreign_key => :ip_location
  belongs_to :vps, :foreign_key => :vps_id
  has_paper_trail

  alias_attribute :addr, :ip_addr
  alias_attribute :version, :ip_v

  include Lockable

  def free?
    vps_id.nil? || vps_id == 0
  end

  # Return first free and unlocked IP address version +v+ from +location+.
  def self.pick_addr!(location, v)
    self.select('vps_ip.*')
      .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = vps_ip.ip_id")
      .where(ip_v: v, location: location)
      .where('vps_id IS NULL')
      .where('rl.id IS NULL')
      .order(:ip_id).take!
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
end
