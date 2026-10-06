# frozen_string_literal: true

require 'digest'
require 'json'

# Retained API responsibility. Neither contract grants physical authority.
class StorageMaintenanceRun < ApplicationRecord
  class UnsupportedRecord < StandardError; end

  RECORD_CONTRACT = 1
  REQUESTED_PROFILE = 'manual_storage_only_v1'
  REVISIONS = { 'reserved' => 1, 'abandoned' => 2 }.freeze
  SUPPORTED_TUPLES = {
    [1, 'reserved', 1].freeze => :active,
    [1, 'abandoned', 2].freeze => :terminal,
    [2, 'handoff_pending', 2].freeze => :active
  }.freeze
  SCOPE_LIMIT = 1_048_576
  POOL_LIMIT = 256
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  DIGEST_PATTERN = /\A[0-9a-f]{64}\z/
  ACQUISITION_FIELDS = %w[request_id record_contract requested_profile freeze_epoch
                          requested_scope_json requested_scope_digest acquired_by_user_id
                          acquired_by_user_session_id acquired_by_user_login acquisition_reason acquired_at].freeze
  ABANDONMENT_FIELDS = %w[abandoned_by_user_id abandoned_by_user_session_id
                          abandoned_by_user_login abandonment_reason abandoned_at].freeze
  HANDOFF_FIELDS = %w[handed_off_by_user_id handed_off_by_user_session_id
                      handed_off_by_user_login handoff_reason handed_off_at].freeze
  POOL_FIELDS = %w[pool_id node_id pool_role filesystem node_role hypervisor_type zpool_guid].freeze

  validate :supported_record
  validate :only_supported_transition, on: :update
  before_destroy { throw :abort }

  def self.request_id!(value)
    raise ArgumentError, 'invalid maintenance request ID' unless value.is_a?(String) && UUID_PATTERN.match?(value)

    value
  end

  def self.pool_ids!(value)
    unless value.is_a?(Array) && value.length.between?(1, POOL_LIMIT) &&
           value.all? { |id| id.is_a?(Integer) && id > 0 } && value.uniq.length == value.length
      raise ArgumentError, 'invalid requested storage pools'
    end

    value.sort
  end

  def self.supported_tuple?(contract, state, revision)
    contract.is_a?(Integer) && revision.is_a?(Integer) && SUPPORTED_TUPLES.has_key?([contract, state, revision])
  end

  def self.active_tuple?(contract, state, revision)
    supported_tuple?(contract, state, revision) && SUPPORTED_TUPLES[[contract, state, revision]] == :active
  end

  def active?
    self.class.active_tuple?(record_contract, state, revision)
  end

  def supported!
    raise UnsupportedRecord, 'unsupported storage maintenance record' unless valid?

    self
  end

  def requested_scope
    JSON.parse(requested_scope_json)
  end

  def summary
    supported!
    attributes.symbolize_keys.slice(
      :id, :request_id, :record_contract, :requested_profile, :state, :revision,
      :freeze_epoch, :requested_scope_digest, *ACQUISITION_FIELDS.map(&:to_sym),
      *ABANDONMENT_FIELDS.map(&:to_sym), *HANDOFF_FIELDS.map(&:to_sym)
    ).except(:requested_scope_json).merge(
      requested_pool_ids: requested_scope.fetch('pools').map { |pool| pool.fetch('pool_id') }
    )
  end

  private

  def supported_record
    errors.add(:request_id, 'is invalid') unless request_id.is_a?(String) && UUID_PATTERN.match?(request_id)
    unless self.class.supported_tuple?(record_contract, state, revision) && requested_profile == REQUESTED_PROFILE
      errors.add(:record_contract, 'is unsupported')
    end
    errors.add(:freeze_epoch, 'is invalid') unless freeze_epoch.is_a?(Integer) && freeze_epoch >= 0
    actor_fields('acquired')
    safe_text(:acquisition_reason, 255)
    errors.add(:acquired_at, 'is required') unless acquired_at
    if state == 'abandoned'
      actor_fields('abandoned')
      safe_text(:abandonment_reason, 255)
      errors.add(:abandoned_at, 'is required') unless abandoned_at
    elsif ABANDONMENT_FIELDS.any? { |field| !self[field].nil? }
      errors.add(:state, 'has unexpected abandonment audit')
    end
    if state == 'handoff_pending'
      actor_fields('handed_off')
      safe_text(:handoff_reason, 255)
      errors.add(:handed_off_at, 'is required') unless handed_off_at
    elsif HANDOFF_FIELDS.any? { |field| !self[field].nil? }
      errors.add(:state, 'has unexpected handoff audit')
    end
    validate_scope
    return unless new_record? && [record_contract, state, revision] != [1, 'reserved', 1]

    errors.add(:state, 'must begin with an API-only reservation')
  end

  def actor_fields(prefix)
    %w[user_id user_session_id].each do |suffix|
      key = "#{prefix}_by_#{suffix}"
      errors.add(key, 'is invalid') unless self[key].is_a?(Integer) && self[key] > 0
    end
    safe_text("#{prefix}_by_user_login", 128)
  end

  def safe_text(key, limit)
    value = self[key]
    unless value.is_a?(String) && value == value.strip && value.length.between?(1, limit) &&
           !value.match?(/[[:cntrl:]]/)
      errors.add(key, 'is invalid')
    end
  end

  def validate_scope
    unless requested_scope_json.is_a?(String) && requested_scope_json.bytesize <= SCOPE_LIMIT &&
           requested_scope_digest.is_a?(String) && DIGEST_PATTERN.match?(requested_scope_digest) &&
           Digest::SHA256.hexdigest(requested_scope_json) == requested_scope_digest
      errors.add(:requested_scope_json, 'is invalid')
      return
    end

    scope = requested_scope
    pools = scope.is_a?(Hash) && scope.keys == ['pools'] && scope['pools']
    ids = pools.is_a?(Array) && pools.map { |pool| pool.is_a?(Hash) && pool['pool_id'] }
    self.class.pool_ids!(ids)
    unless ids == ids.sort && pools.all? { |pool| valid_pool_claim?(pool) } && JSON.generate(scope) == requested_scope_json
      errors.add(:requested_scope_json, 'is not canonical catalog scope')
    end
  rescue JSON::ParserError, ArgumentError
    errors.add(:requested_scope_json, 'is invalid')
  end

  def valid_pool_claim?(pool)
    pool.keys == POOL_FIELDS && pool['node_id'].is_a?(Integer) && pool['node_id'] > 0 &&
      Pool.roles.has_key?(pool['pool_role']) && Node.roles.has_key?(pool['node_role']) &&
      Node.hypervisor_types.has_key?(pool['hypervisor_type']) && pool['filesystem'].is_a?(String) &&
      !pool['filesystem'].empty? && (pool['zpool_guid'].nil? ||
        (pool['zpool_guid'].is_a?(String) && pool['zpool_guid'].match?(/\A(?:0|[1-9][0-9]*)\z/) &&
         pool['zpool_guid'].to_i <= 18_446_744_073_709_551_615))
  end

  def only_supported_transition
    return unless has_changes_to_save?

    predecessor = [record_contract_in_database, state_in_database, revision_in_database]
    successor = [record_contract, state, revision]
    audit = if predecessor == [1, 'reserved', 1] && successor == [1, 'abandoned', 2]
              ABANDONMENT_FIELDS
            elsif predecessor == [1, 'reserved', 1] && successor == [2, 'handoff_pending', 2]
              HANDOFF_FIELDS + ['record_contract']
            end
    unless audit && (changes_to_save.keys - (audit + %w[state revision])).empty? &&
           (audit - ['record_contract']).all? { |field| attribute_in_database(field).nil? && !self[field].nil? }
      errors.add(:base, 'maintenance audit is immutable')
    end
  end
end
