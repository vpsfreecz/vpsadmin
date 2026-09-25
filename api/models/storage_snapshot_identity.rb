module StorageSnapshotIdentity
  extend ActiveSupport::Concern

  included do
    enum :physical_presence, %i[unknown present missing], prefix: :physical
    validate :physical_identity_on_supported_pool
    validate :present_snapshot_has_identity
    validates :zfs_guid, :zfs_owner_fs_guid,
              numericality: { greater_than_or_equal_to: 0,
                              less_than_or_equal_to: 18_446_744_073_709_551_615 },
              allow_nil: true
  end

  private

  def physical_identity_on_supported_pool
    return if physical_identity_pool_supported?
    return if zfs_guid.nil? && zfs_owner_fs_guid.nil? && zfs_path.nil? &&
              physical_unknown?

    errors.add(:base, 'physical identity is stored on the wrong snapshot occurrence')
  end

  def present_snapshot_has_identity
    return unless physical_present?

    %i[zfs_path zfs_guid zfs_owner_fs_guid].each do |attribute|
      errors.add(attribute, 'is required for a present snapshot') if public_send(attribute).nil?
    end
  end
end
