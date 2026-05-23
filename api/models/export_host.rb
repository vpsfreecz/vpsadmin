class ExportHost < ApplicationRecord
  belongs_to :export
  belongs_to :ip_address

  validate :check_ip_owner

  protected

  def check_ip_owner
    return if export.nil? || ip_address.nil?

    owner = ip_address.current_owner
    return if owner.nil? || owner == export.user

    errors.add(:ip_address, 'must belong to the export owner')
  end
end
