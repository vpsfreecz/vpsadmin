# frozen_string_literal: true

require 'digest'
require 'json'

# API-only reservation. Contract 1 cannot accept physical responsibilities.
class StorageMaintenanceRun < ApplicationRecord
  class UnsupportedRecord < StandardError; end

  RECORD_CONTRACT = 1
  REQUESTED_PROFILE = 'manual_storage_only_v1'
  REVISIONS = { 'reserved' => 1, 'abandoned' => 2 }.freeze
  SCOPE_LIMIT = 1_048_576
  POOL_LIMIT = 256
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  DIGEST_PATTERN = /\A[0-9a-f]{64}\z/
  ACQUISITION_FIELDS = %w[request_id record_contract requested_profile freeze_epoch
                          requested_scope_json requested_scope_digest acquired_by_user_id
                          acquired_by_user_session_id acquired_by_user_login acquisition_reason acquired_at].freeze
  ABANDONMENT_FIELDS = %w[abandoned_by_user_id abandoned_by_user_session_id
                          abandoned_by_user_login abandonment_reason abandoned_at].freeze
  POOL_FIELDS = %w[pool_id node_id pool_role filesystem node_role hypervisor_type zpool_guid].freeze

  validate :supported_record
  validate :only_terminal_transition, on: :update
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
      *ABANDONMENT_FIELDS.map(&:to_sym)
    ).except(:requested_scope_json).merge(
      requested_pool_ids: requested_scope.fetch('pools').map { |pool| pool.fetch('pool_id') }
    )
  end

  private

  def supported_record
    errors.add(:request_id, 'is invalid') unless request_id.is_a?(String) && UUID_PATTERN.match?(request_id)
    unless record_contract.is_a?(Integer) && record_contract == RECORD_CONTRACT &&
           requested_profile == REQUESTED_PROFILE && revision.is_a?(Integer) && REVISIONS[state] == revision
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
    validate_scope
    errors.add(:state, 'must begin reserved') if new_record? && state != 'reserved'
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

  def only_terminal_transition
    immutable = (changes_to_save.keys - (ABANDONMENT_FIELDS + %w[state revision])).any?
    terminal = state_in_database == 'reserved' && revision_in_database == 1 &&
               state == 'abandoned' && revision == 2 &&
               ABANDONMENT_FIELDS.all? { |field| attribute_in_database(field).nil? && !self[field].nil? }
    errors.add(:base, 'maintenance audit is immutable') if immutable || (has_changes_to_save? && !terminal)
  end
end
