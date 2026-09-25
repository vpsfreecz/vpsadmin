require 'digest'
require 'securerandom'

# Observer-mode intent. Opaque handles cover every pool on their node until an
# exact effect manifest exists; they cannot be used to assert a verified scope.
class StorageMutationJournal
  PROTOCOL_VERSION = 1
  OBSERVER_POOL_BATCH_SIZE = 64
  MAX_GROUP_SNAPSHOTS = 32

  def self.strict_mode?
    false # Enable only after every physical handle has bounded guards.
  end

  def self.mark_catalog_topology!(dataset_in_pools)
    dips = dataset_in_pools.uniq(&:id)
    dips.map(&:pool).uniq(&:id).each { |pool| advance_scope!(pool) }
    dips.each { |dip| advance_scope!(dip.pool, dip) }
  end

  def self.stage!(transaction, input, effect_entry:)
    raise 'storage command has no node' unless transaction.node_id

    subject = transaction.storage_mutation_subject
    group = group_snapshot_manifest(transaction, input) if
      transaction.handle == 5215 && transaction.test_only_strict_group_snapshot?
    if transaction.handle == 5215 && transaction.test_only_strict_group_snapshot? && !group
      raise 'strict group snapshot has no bounded exact manifest'
    end

    if strict_mode?
      raise 'storage effect has no bounded manifest' unless subject || group

      raise 'storage strict-mode guards are not installed'
    end
    impact = StorageEffectRegistry.journal_impact(effect_entry)
    raise 'storage mutation has no verification impact' if impact == :none

    if group
      scopes = [advance_scope!(group.fetch(:pool))]
      member_scopes = group.fetch(:members).map do |member|
        advance_scope!(group.fetch(:pool), member.fetch(:dip))
      end
      subject_scope = nil
    elsif subject
      scopes = [advance_scope!(subject.dataset_in_pool.pool)]
      subject_scope = advance_scope!(subject.dataset_in_pool.pool, subject.dataset_in_pool)
      member_scopes = []
    else
      owner_pool = resolve_owner_pool(transaction, input) if effect_entry.scope_resolver == :owner_pool
      scopes = if owner_pool
                 [advance_scope!(owner_pool)]
               else
                 advance_node_pools!(transaction.node_id)
               end
      subject_scope = nil
      member_scopes = []
    end
    target_kind = case impact
                  when :dependency then 'observer_dependency'
                  when :catalog_identity then 'observer_catalog_identity'
                  else 'observer_unbounded'
                  end
    targets = scopes.map.with_index do |scope, index|
      { scope:, sequence: index, kind: target_kind }
    end
    if group
      group.fetch(:members).each_with_index do |member, index|
        targets << {
          scope: member_scopes.fetch(index), sequence: index + 1,
          kind: 'snapshot_create', snapshot_in_pool: member.fetch(:sip),
          expected_owner_fs_guid: member.fetch(:owner).zfs_guid,
          expected_path: member.fetch(:path)
        }
      end
    elsif subject
      targets << {
        scope: subject_scope,
        sequence: targets.length,
        kind: 'snapshot_create',
        snapshot_in_pool: subject,
        expected_owner_fs_guid: StorageFilesystemIdentity
                                .find_by(dataset_in_pool_id: subject.dataset_in_pool_id)&.zfs_guid,
        expected_path: "#{input.fetch(:pool_fs)}/#{input.fetch(:dataset_name)}@" \
                       "#{input.fetch(:planned_snapshot_name)}"
      }
    end

    digest = Digest::SHA256.hexdigest(JSON.generate({
      registry_version: StorageEffectRegistry::VERSION,
      transaction_id: transaction.id,
      node_id: transaction.node_id,
      handle: transaction.handle,
      input:,
      scopes: (scopes + [subject_scope] + member_scopes).compact.uniq.map do |s|
        [s.id, s.mutation_epoch]
      end,
      targets: targets.map do |target|
        [target[:scope].id, target[:kind], target[:sequence], target[:expected_path],
         target[:expected_owner_fs_guid]]
      end
    }))
    effect_name = transaction.class.storage_effect || effect_entry.execute
    intent = StorageMutationIntent.create!(
      storage_transaction: transaction,
      transaction_chain: transaction.transaction_chain,
      node_id: transaction.node_id,
      kind: if scopes.empty?
              "observer_unbounded_#{impact}_#{effect_name}"
            elsif %i[dependency catalog_identity].include?(impact)
              "#{impact}_#{effect_name}"
            else
              effect_name.to_s
            end,
      token: SecureRandom.hex(32),
      protocol_version: PROTOCOL_VERSION,
      manifest_digest: digest
    )
    intent_scopes = (scopes + [subject_scope] + member_scopes).compact.uniq.to_h do |scope|
      [scope.id, StorageMutationIntentScope.create!(
        storage_mutation_intent: intent,
        storage_integrity_scope: scope,
        expected_epoch: scope.mutation_epoch
      )]
    end
    targets.each do |target|
      StorageMutationTarget.create!(
        storage_mutation_intent: intent,
        storage_mutation_intent_scope: intent_scopes.fetch(target[:scope].id),
        snapshot_in_pool: target[:snapshot_in_pool],
        expected_path: target[:expected_path],
        expected_owner_fs_guid: target[:expected_owner_fs_guid],
        command_key: transaction.handle.to_s,
        sequence: target[:sequence],
        kind: target[:kind]
      )
    end

    return unless (transaction.class.storage_effect == :snapshot_create && subject) || group

    { token: intent.token, manifest_digest: intent.manifest_digest,
      protocol_version: PROTOCOL_VERSION,
      registry_version: StorageEffectRegistry::VERSION }
  end

  # Return nil for legacy/opaque groups: they remain admitted in observer mode,
  # while test-only strict dispatch refuses them because no guard is issued.
  def self.group_snapshot_manifest(transaction, input)
    rows = input[:snapshots] || input['snapshots']
    name = input[:planned_snapshot_name] || input['planned_snapshot_name']
    return unless rows.is_a?(Array) && rows.length.between?(1, MAX_GROUP_SNAPSHOTS)
    return unless name.is_a?(String) && name.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/)
    return unless rows.all?(Hash)

    snapshot_ids = rows.map { |row| row[:snapshot_id] || row['snapshot_id'] }
    return unless snapshot_ids.all? { |id| id.is_a?(Integer) && id > 0 }
    return unless snapshot_ids.uniq.length == rows.length

    candidates = SnapshotInPool.includes(:snapshot, dataset_in_pool: %i[pool dataset])
                               .where(snapshot_id: snapshot_ids).to_a
    members = rows.filter_map do |row|
      matches = candidates.select do |sip|
        dip = sip.dataset_in_pool
        sip.snapshot_id == (row[:snapshot_id] || row['snapshot_id']) &&
          dip.pool.filesystem == (row[:pool_fs] || row['pool_fs']) &&
          dip.dataset.full_name == (row[:dataset_name] || row['dataset_name']) &&
          sip.snapshot.name.delete_suffix(' (unconfirmed)') == name
      end
      next unless matches.one?

      sip = matches.first
      { sip:, dip: sip.dataset_in_pool }
    end
    return unless members.length == rows.length

    return unless members.map { |member| member.fetch(:sip).id } == members.map { |member| member.fetch(:sip).id }.sort
    return unless members.map { |member| member.fetch(:dip).id }.uniq.length == members.length

    pool = members.first.fetch(:dip).pool
    return if pool.backup? || pool.node_id != transaction.node_id
    return unless members.all? { |member| member.fetch(:dip).pool_id == pool.id }

    owners = StorageFilesystemIdentity.where(dataset_in_pool_id: members.map { |m| m.fetch(:dip).id })
                                      .group_by(&:dataset_in_pool_id)
    owners_valid = members.all? do |member|
      dip = member.fetch(:dip)
      owner_path = "#{pool.filesystem}/#{dip.dataset.full_name}"
      matches = owners[dip.id]
      next false unless matches&.one?

      owner = matches.first
      next false unless owner.physical_present? && owner.pool_id == pool.id &&
                        owner.node_id == transaction.node_id && owner.zfs_path == owner_path &&
                        owner.path_digest == Digest::SHA256.hexdigest(owner_path) &&
                        owner.zfs_guid.to_i > 0

      member[:owner] = owner
      member[:path] = "#{owner_path}@#{name}"
      true
    end
    return unless owners_valid

    return unless members.map { |member| member.fetch(:path) }.uniq.length == members.length

    { pool:, members: }
  end
  private_class_method :group_snapshot_manifest

  def self.advance_node_pools!(node_id)
    scopes = []
    # find_each uses ascending primary-key batches. The caller's staging
    # transaction keeps the freeze lock and all epoch changes until commit.
    Pool.where(node_id:).find_each(batch_size: OBSERVER_POOL_BATCH_SIZE) do |pool|
      scopes << advance_scope!(pool)
    end
    scopes
  end
  private_class_method :advance_node_pools!

  def self.resolve_owner_pool(transaction, input)
    pool_fs = input[:pool_fs] || input['pool_fs']
    pool_from_path = nil
    if pool_fs
      matches = Pool.where(node_id: transaction.node_id, filesystem: pool_fs).limit(2).to_a
      return unless matches.one?

      pool_from_path = matches.first
    end

    export_id = input[:export_id] || input['export_id']
    return pool_from_path unless export_id

    pool_from_export = Export.includes(dataset_in_pool: :pool)
                             .find_by(id: export_id)&.dataset_in_pool&.pool
    return pool_from_path unless pool_from_export
    return unless pool_from_export.node_id == transaction.node_id
    return if pool_from_path && pool_from_path.id != pool_from_export.id

    pool_from_export
  end
  private_class_method :resolve_owner_pool

  def self.advance_scope!(pool, dataset_in_pool = nil)
    key = dataset_in_pool ? "dip:#{dataset_in_pool.id}" : "pool:#{pool.id}"
    scope = StorageIntegrityScope.find_or_initialize_by(scope_key: key)
    if scope.new_record?
      scope.pool = pool
      scope.dataset_in_pool = dataset_in_pool if dataset_in_pool
      scope.save!
    end
    scope.lock!
    scope.pool = pool
    scope.dataset_in_pool = dataset_in_pool if dataset_in_pool
    state = scope.needs_reconcile? ? :needs_reconcile : :unverified
    scope.update!(mutation_epoch: scope.mutation_epoch + 1, state:)
    scope
  end
  private_class_method :advance_scope!
end
