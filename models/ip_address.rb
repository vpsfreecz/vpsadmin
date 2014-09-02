class IpAddress < ActiveRecord::Base
  self.table_name = 'vps_ip'
  self.primary_key = 'ip_id'

  belongs_to :location, :foreign_key => :ip_location
  belongs_to :vps, :foreign_key => :vps_id
  has_paper_trail

  alias_attribute :addr, :ip_addr
  alias_attribute :version, :ip_v

  after_update :shaper_changed, if: :shaper_changed?

  def free?
    vps_id.nil? || vps_id == 0
  end

  def self.pick_addr!(location, v)
    self.where(ip_v: v, location: location)
      .where('vps_id IS NULL OR vps_id = 0')
      .order(:ip_id).take!
  end

  protected
  def shaper_changed?
    max_tx_changed? || max_rx_changed?
  end

  def shaper_changed
    Transactions::Vps::ShaperChange.fire(self) if vps_id > 0
  end
end
