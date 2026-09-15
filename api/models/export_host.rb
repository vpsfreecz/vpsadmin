class ExportHost < ApplicationRecord
  belongs_to :export
  belongs_to :ip_address

  validate :check_ip_address

  def self.ip_address_assigned_to_export_owner_vps?(export, ip_address)
    return false if export.nil? || ip_address.nil?

    ip_address.network_interface&.vps&.user_id == export.user_id
  end

  # Serialize grant changes with assignment and ownership changes, including
  # confirmations which can recreate a deleted grant on rollback.
  def lock_ip!(chain, reserved: false)
    ip = ip_address
    if reserved
      ip.require_reservation!(chain)
      return
    end

    identity = [ip.user_id, ip.network_interface_id, ip.network_interface&.vps&.user_id]
    ip.lock_current!(chain)
    ip.reload_current_assignment!
    return if identity == [ip.user_id, ip.network_interface_id, ip.network_interface&.vps&.user_id]

    errors.add(:ip_address, 'ownership or assignment changed; retry the operation')
    raise ActiveRecord::RecordInvalid, self
  end

  protected

  def check_ip_address
    return if export.nil? || ip_address.nil?
    return if ::User.current&.role == :admin
    return if self.class.ip_address_assigned_to_export_owner_vps?(export, ip_address)

    errors.add(:ip_address, 'must be assigned to a VPS owned by the export owner')
  end
end
