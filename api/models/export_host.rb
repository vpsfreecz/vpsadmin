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
  def lock_ip!(chain)
    ip = ip_address
    identity = [ip.user_id, ip.network_interface_id]
    # Included route chains can carry an assignment pending confirmation.
    # They already hold the IP lock; preserve that intended in-memory state.
    return unless chain.lock(ip)

    ip.reload(lock: true)
    return if identity == [ip.user_id, ip.network_interface_id]

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
