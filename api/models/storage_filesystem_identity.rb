require 'digest'

class StorageFilesystemIdentity < ApplicationRecord
  MAX_ZFS_GUID = (1 << 64) - 1

  # Do not publish catalog-linked identities while legacy writers can run.
  # RESTRICT owner/origin FKs are safe only after the guarded-writer cutover.
  belongs_to :node
  belongs_to :pool
  belongs_to :owner_pool, class_name: 'Pool', optional: true
  belongs_to :dataset_in_pool, optional: true
  belongs_to :dataset_tree, optional: true
  belongs_to :branch, optional: true
  belongs_to :snapshot_in_pool_clone, optional: true
  belongs_to :origin_snapshot_in_pool, class_name: 'SnapshotInPool', optional: true
  belongs_to :origin_snapshot_in_pool_in_branch,
             class_name: 'SnapshotInPoolInBranch', optional: true
  belongs_to :storage_observation_run, optional: true

  enum :physical_presence, %i[unknown present missing], prefix: :physical
  enum :origin_state, %i[unknown none linked unresolved], prefix: :origin

  validates :zfs_guid,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: MAX_ZFS_GUID
            },
            allow_nil: true
  validate :one_catalog_owner
  validate :owner_in_pool
  validate :origin_link_consistent
  validate :node_matches_pool
  validate :unique_node_path_claim
  validate :present_filesystem_has_identity
  before_validation :set_path_digest
  before_validation :set_node

  def catalog_owner
    owner_pool || dataset_in_pool || dataset_tree || branch || snapshot_in_pool_clone
  end

  private

  def one_catalog_owner
    count = %i[owner_pool dataset_in_pool dataset_tree branch snapshot_in_pool_clone]
            .count { |name| public_send(name).present? }
    errors.add(:base, 'exactly one catalog owner is required') unless count == 1
  end

  def owner_in_pool
    owner_pool_id = owner_pool&.id
    owner_pool_id ||= dataset_in_pool&.pool_id
    owner_pool_id ||= dataset_tree&.dataset_in_pool&.pool_id
    branch_dip = branch&.dataset_tree&.dataset_in_pool
    owner_pool_id ||= branch_dip&.pool_id
    clone_dip = snapshot_in_pool_clone&.snapshot_in_pool&.dataset_in_pool
    owner_pool_id ||= clone_dip&.pool_id
    return if owner_pool_id.nil? || owner_pool_id == pool_id

    errors.add(:pool, 'must contain the catalog owner')
  end

  def origin_link_consistent
    count = [origin_snapshot_in_pool, origin_snapshot_in_pool_in_branch].count(&:present?)
    if origin_linked?
      errors.add(:base, 'linked origin requires exactly one snapshot occurrence') unless count == 1
    elsif count != 0
      errors.add(:base, 'origin reference requires linked origin state')
    end

    source_pool_id = nil
    if origin_snapshot_in_pool
      source_dip = origin_snapshot_in_pool.dataset_in_pool
      source_pool_id = source_dip&.pool_id
      if source_dip&.pool&.backup?
        errors.add(:base, 'backup origin must identify a branch occurrence')
      end
    elsif origin_snapshot_in_pool_in_branch
      source_sip = origin_snapshot_in_pool_in_branch.snapshot_in_pool
      source_branch = origin_snapshot_in_pool_in_branch.branch
      source_dip = source_sip&.dataset_in_pool
      branch_dip = source_branch&.dataset_tree&.dataset_in_pool
      source_pool_id = branch_dip&.pool_id
      unless source_dip&.pool&.backup? && source_dip&.id == branch_dip&.id
        errors.add(:base, 'backup origin branch must match its snapshot placement')
      end
    end
    return if source_pool_id.nil? || source_pool_id == pool_id

    errors.add(:base, 'origin snapshot must belong to the same pool')
  end

  def set_path_digest
    self.path_digest = zfs_path.nil? ? nil : Digest::SHA256.hexdigest(zfs_path.b)
  end

  def set_node
    self.node ||= pool&.node
  end

  def node_matches_pool
    return unless node && pool
    return if node_id == pool.node_id

    errors.add(:node, 'must own the pool')
  end

  def unique_node_path_claim
    return unless node_id && path_digest

    existing = self.class.where(node_id:, path_digest:).where.not(id: id).pick(:zfs_path)
    return unless existing

    if existing == zfs_path
      errors.add(:zfs_path, 'is already claimed on this node')
    else
      errors.add(:path_digest, 'collides with another path on this node')
    end
  end

  def present_filesystem_has_identity
    return unless physical_present?

    %i[zfs_path zfs_guid].each do |attribute|
      errors.add(attribute, 'is required for a present filesystem') if public_send(attribute).nil?
    end
  end
end
