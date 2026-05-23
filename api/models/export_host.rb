class ExportHost < ApplicationRecord
  belongs_to :export
  belongs_to :ip_address

  validate :check_ip_address

  def self.ip_address_assigned_to_export_owner_vps?(export, ip_address)
    return false if export.nil? || ip_address.nil?

    ip_address.network_interface&.vps&.user_id == export.user_id
  end

  protected

  def check_ip_address
    return if export.nil? || ip_address.nil?
    return if ::User.current&.role == :admin
    return if self.class.ip_address_assigned_to_export_owner_vps?(export, ip_address)

    errors.add(:ip_address, 'must be assigned to a VPS owned by the export owner')
  end
end
