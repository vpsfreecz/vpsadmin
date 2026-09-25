# frozen_string_literal: true

# Bounded DB control-flow status. A drained result is not physical proof:
# osctld children, asynchronous GC and the ZFS graph need separate checks.
class StorageFreezeStatus
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end

  class Control < Record
    self.table_name = 'storage_freeze_controls'
  end

  class Chain < Record
    self.table_name = 'transaction_chains'
  end

  class TransactionRow < Record
    self.table_name = 'transactions'
  end

  class Confirmation < Record
    self.table_name = 'transaction_confirmations'
  end

  class Intent < Record
    self.table_name = 'storage_mutation_intents'
  end

  class Attempt < Record
    self.table_name = 'storage_mutation_attempts'
  end

  class Lock < Record
    self.table_name = 'resource_locks'
  end

  SAMPLE_LIMIT = 20
  COUNT_CAP = 1000
  ACTIVE_CHAIN_STATES = [0, 1, 3].freeze
  BLOCKING_INTENT_PHASES = [0, 1, 5].freeze
  MODES = { 0 => 'read_write', 1 => 'read_only' }.freeze

  def self.snapshot
    before = Control.find(1)
    handles = StorageEffectRegistry::ENTRIES.filter_map do |handle, entry|
      handle if entry.admission_required
    end
    chain_types = StorageEffectRegistry::CHAIN_EFFECTS.keys
    # The active query starts from the indexed chain state. The waiting query
    # starts from the done=0 index. Neither scans all historical handles.
    active_chains = Chain.where(state: ACTIVE_CHAIN_STATES)
    active_chains = active_chains.where(chain_membership_sql, handles, chain_types)
    fatal_chains = Chain.where(state: [5, 6])
    fatal_chains = fatal_chains.where(chain_membership_sql, handles, chain_types)
    waiting_transactions = TransactionRow.where(done: 0)
    waiting_transactions = waiting_transactions.where(transaction_membership_sql, handles, chain_types)
    pending_confirmations = Confirmation.where(done: 0)
    pending_confirmations = pending_confirmations.joins(
      'INNER JOIN transactions ON transactions.id = transaction_confirmations.transaction_id'
    )
    pending_confirmations = pending_confirmations.where(
      transaction_membership_sql, handles, chain_types
    )
    intents = Intent.all
    attempts = Attempt.all
    locks = Lock.where(locked_by_type: 'TransactionChain')
    locks = locks.where(lock_membership_sql, handles, chain_types)

    relations = {
      active_chains: active_chains,
      fatal_or_unreviewed_resolved_chains: fatal_chains,
      waiting_transactions: waiting_transactions,
      pending_confirmations: pending_confirmations,
      prepared_intents: intents.where(phase: 0),
      executing_intents: intents.where(phase: 1),
      needs_reconcile_intents: intents.where(phase: 5),
      started_attempts: attempts.where(state: 0),
      uncertain_attempts: attempts.where(state: 3),
      retained_chain_locks: locks,
      settled_unverified_intents: intents.where(phase: 6)
    }
    counts = {}
    capped = []
    relations.each do |name, relation|
      ids = relation.limit(COUNT_CAP + 1).pluck(relation.klass.arel_table[:id])
      counts[name] = [ids.length, COUNT_CAP].min
      capped << name if ids.length > COUNT_CAP
    end
    after = Control.find(1)
    mode = MODES.fetch(after.mode) { raise 'invalid storage freeze mode' }
    stable = before.epoch == after.epoch && before.mode == after.mode
    blockers = counts.except(:settled_unverified_intents)
    sample_intent_ids = intents.where(phase: BLOCKING_INTENT_PHASES)
                               .order(:id).limit(SAMPLE_LIMIT).pluck(:id)

    {
      mode: mode,
      epoch: after.epoch,
      stable_epoch: stable,
      counts: counts,
      count_capped: capped,
      sample_chain_ids: active_chains.order(:id).limit(SAMPLE_LIMIT).pluck(:id),
      sample_fatal_chain_ids: fatal_chains.order(:id).limit(SAMPLE_LIMIT).pluck(:id),
      sample_intent_ids: sample_intent_ids,
      db_drained: stable && mode == 'read_only' && blockers.values.all?(&:zero?),
      repair_ready: false
    }
  end

  def self.chain_membership_sql
    <<~SQL.squish
      (EXISTS (SELECT 1 FROM transactions storage_t
              WHERE storage_t.transaction_chain_id = transaction_chains.id
                AND storage_t.handle IN (?))
      OR EXISTS (SELECT 1 FROM storage_mutation_intents storage_i
                 WHERE storage_i.transaction_chain_id = transaction_chains.id)
      OR transaction_chains.type IN (?))
    SQL
  end
  private_class_method :chain_membership_sql

  def self.transaction_membership_sql
    <<~SQL.squish
      (EXISTS (SELECT 1 FROM transactions storage_t
              WHERE storage_t.transaction_chain_id = transactions.transaction_chain_id
                AND storage_t.handle IN (?))
      OR EXISTS (SELECT 1 FROM storage_mutation_intents storage_i
                 WHERE storage_i.transaction_chain_id = transactions.transaction_chain_id)
      OR EXISTS (SELECT 1 FROM transaction_chains storage_ch
                 WHERE storage_ch.id = transactions.transaction_chain_id
                   AND storage_ch.type IN (?)))
    SQL
  end
  private_class_method :transaction_membership_sql

  def self.lock_membership_sql
    <<~SQL.squish
      (EXISTS (SELECT 1 FROM transactions storage_t
              WHERE storage_t.transaction_chain_id = resource_locks.locked_by_id
                AND storage_t.handle IN (?))
      OR EXISTS (SELECT 1 FROM storage_mutation_intents storage_i
                 WHERE storage_i.transaction_chain_id = resource_locks.locked_by_id)
      OR EXISTS (SELECT 1 FROM transaction_chains storage_ch
                 WHERE storage_ch.id = resource_locks.locked_by_id
                   AND storage_ch.type IN (?)))
    SQL
  end
  private_class_method :lock_membership_sql

  def self.drain(timeout:, interval: 2)
    raise ArgumentError, 'timeout must be positive' unless timeout > 0
    raise ArgumentError, 'interval must be positive' unless interval > 0

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = snapshot
      raise ArgumentError, 'drain requires read-only mode' unless result[:mode] == 'read_only'
      return result if result[:db_drained]

      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return result if remaining <= 0

      sleep [remaining, interval].min
    end
  end
end
