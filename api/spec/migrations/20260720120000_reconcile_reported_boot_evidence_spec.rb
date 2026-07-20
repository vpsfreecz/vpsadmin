# frozen_string_literal: true

require_relative '../migration_helper'

module VpsAdmin
  module API; end
end

require_relative '../../lib/vpsadmin/api/kernel_evidence/revision'

MigrationSpecSupport.require_migration('20260720120000_reconcile_reported_boot_evidence')

RSpec.describe ReconcileReportedBootEvidence do
  before do
    define_schema do
      create_table :node_statuses do |t|
        t.datetime :created_at, null: false
      end

      create_table :node_kernel_evidences do |t|
        t.integer :snapshot_type, null: false
        t.datetime :booted_at
      end

      create_table :node_kernel_evidence_errors do |t|
        t.bigint :node_kernel_evidence_id, null: false
        t.string :component, null: false
        t.string :reason, null: false
      end

      create_table :node_kernel_events do |t|
        t.bigint :node_id, null: false
        t.bigint :node_kernel_evidence_id
        t.bigint :source_status_id
        t.integer :event_type, null: false
        t.integer :source, null: false
        t.integer :confidence, null: false
        t.datetime :booted_at
        t.string :booted_release
        t.datetime :effective_at
        t.datetime :observed_after
        t.datetime :observed_before, null: false
        t.boolean :current, null: false, default: false
        t.timestamps null: false
      end
    end
  end

  it 'corrects reported boots and deletes one matched reconstructed duplicate' do
    exact_evidence = evidence(booted_at: timestamp)
    estimated_evidence = evidence(booted_at: timestamp)
    incomplete_evidence = evidence(booted_at: nil)
    current_evidence = evidence(booted_at: timestamp, snapshot_type: 0)
    insert_row(
      :node_kernel_evidence_errors,
      node_kernel_evidence_id: estimated_evidence,
      component: 'booted_at',
      reason: 'estimated_from_uptime'
    )
    source_status = insert_row(:node_statuses, created_at: timestamp + 1.minute)

    reconstructed = event(
      nil,
      source: 0,
      source_status_id: source_status,
      booted_at: timestamp - 1.minute,
      observed_before: timestamp + 1.minute,
      current: true
    )
    second_reconstructed = event(
      nil,
      source: 0,
      booted_at: timestamp + 2.minutes,
      observed_before: timestamp + 90.seconds
    )
    exact = event(
      exact_evidence,
      booted_at: nil,
      observed_before: timestamp + 2.minutes
    )
    estimated = event(
      estimated_evidence,
      node_id: 2,
      confidence: 2,
      observed_before: timestamp + 2.minutes
    )
    incomplete = event(incomplete_evidence, node_id: 3, confidence: 0)
    unmatched_reconstructed = event(
      nil,
      node_id: 4,
      source: 0,
      booted_at: timestamp - 1.hour,
      observed_before: timestamp - 50.minutes
    )
    unmatched_report = event(
      exact_evidence,
      node_id: 4,
      effective_at: timestamp + 10.minutes,
      observed_before: timestamp + 2.minutes
    )
    actual_reboot = event(
      exact_evidence,
      node_id: 8,
      observed_after: timestamp + 1.minute,
      observed_before: timestamp + 2.minutes
    )
    runtime = event(exact_evidence, node_id: 5, event_type: 1)
    current_snapshot = event(current_evidence, node_id: 6)
    without_evidence = event(nil, node_id: 7)

    exact_revision = event_revision(exact)
    collection_revision = current_collection_revision

    migrate_up!

    expect(column_exists?(:node_kernel_events, :superseded_by_event_id)).to be(false)
    expect(find_rows(:node_kernel_events, { id: reconstructed })).to be_empty
    expect(row(exact)).to include(
      'confidence' => 2,
      'effective_at' => timestamp
    )
    expect(boolish(row(exact).fetch('current'))).to be(true)
    expect(row(second_reconstructed)).to include('source' => 0)
    expect(boolish(row(second_reconstructed).fetch('current'))).to be(false)
    expect(row(estimated)).to include('confidence' => 1, 'effective_at' => timestamp)
    expect(row(incomplete)).to include('confidence' => 0, 'effective_at' => nil)
    expect(row(unmatched_reconstructed)).to include('source' => 0)
    expect(row(unmatched_report)).to include('confidence' => 2, 'effective_at' => timestamp)
    expect(row(actual_reboot)).to include('confidence' => 2, 'effective_at' => timestamp)
    expect(row(runtime)).to include('confidence' => 1, 'effective_at' => nil)
    expect(row(current_snapshot)).to include('confidence' => 1, 'effective_at' => nil)
    expect(row(without_evidence)).to include('confidence' => 1, 'effective_at' => nil)
    expect(row(exact).fetch('updated_at')).to be > initial_event_timestamp
    expect(row(estimated).fetch('updated_at')).to be > initial_event_timestamp
    expect(row(runtime).fetch('updated_at')).to eq(initial_event_timestamp)
    expect(event_revision(exact)).not_to eq(exact_revision)
    expect(current_collection_revision).not_to eq(collection_revision)
    expect(row_count(:node_kernel_events)).to eq(10)
    expect(row_count(:node_kernel_evidences)).to eq(4)
    expect(row_count(:node_statuses)).to eq(1)

    updated_at_by_id = rows(:node_kernel_events).to_h do |event_row|
      [event_row.fetch('id'), event_row.fetch('updated_at')]
    end
    exact_revision = event_revision(exact)
    collection_revision = current_collection_revision

    migrate_up!

    expect(
      rows(:node_kernel_events).to_h do |event_row|
        [event_row.fetch('id'), event_row.fetch('updated_at')]
      end
    ).to eq(updated_at_by_id)
    expect(rows(:node_kernel_events).map { |event| event.fetch('id') }).to include(second_reconstructed)
    expect(event_revision(exact)).to eq(exact_revision)
    expect(current_collection_revision).to eq(collection_revision)
  end

  it 'leaves corrected data and the deleted derived duplicate unchanged on rollback' do
    exact_evidence = evidence(booted_at: timestamp)
    estimated_evidence = evidence(booted_at: timestamp)
    insert_row(
      :node_kernel_evidence_errors,
      node_kernel_evidence_id: estimated_evidence,
      component: 'booted_at',
      reason: 'estimated_from_uptime'
    )
    source_status = insert_row(:node_statuses, created_at: timestamp + 1.minute)
    reconstructed = event(
      nil,
      source: 0,
      source_status_id: source_status,
      booted_at: timestamp - 1.minute,
      observed_before: timestamp + 1.minute,
      current: true
    )
    reported = event(exact_evidence, observed_before: timestamp + 2.minutes)
    estimated = event(
      estimated_evidence,
      node_id: 2,
      confidence: 2,
      observed_before: timestamp + 2.minutes
    )

    migrate_up!
    expect(find_rows(:node_kernel_events, { id: reconstructed })).to be_empty
    expect(row(reported)).to include('confidence' => 2, 'effective_at' => timestamp)
    expect(boolish(row(reported).fetch('current'))).to be(true)
    expect(row(estimated)).to include('confidence' => 1, 'effective_at' => timestamp)

    corrected_rows = rows(:node_kernel_events)
    reported_revision = event_revision(reported)
    collection_revision = current_collection_revision

    migrate_down!

    expect(column_exists?(:node_kernel_events, :superseded_by_event_id)).to be(false)
    expect(rows(:node_kernel_events)).to eq(corrected_rows)
    expect(event_revision(reported)).to eq(reported_revision)
    expect(current_collection_revision).to eq(collection_revision)
    expect(row_count(:node_kernel_evidences)).to eq(2)
    expect(row_count(:node_kernel_evidence_errors)).to eq(1)
    expect(row_count(:node_statuses)).to eq(1)
  end

  it 'leaves a bootstrap outside the captured ID set for runtime reconciliation' do
    source_status = insert_row(:node_statuses, created_at: timestamp + 1.minute)
    reconstructed = event(
      nil,
      source: 0,
      source_status_id: source_status,
      booted_at: timestamp - 1.minute,
      observed_before: timestamp + 1.minute,
      current: true
    )
    reported = nil
    migration = described_class.new
    allow(migration).to receive(:reported_boot_ids_needing_reconciliation)
      .and_wrap_original do |original|
      reported_ids = original.call
      reported = event(
        evidence(booted_at: timestamp),
        observed_before: timestamp + 2.minutes
      )
      reported_ids
    end

    migration.migrate(:up)

    expect(row(reported)).to include(
      'confidence' => 1,
      'effective_at' => nil,
      'updated_at' => initial_event_timestamp
    )
    expect(row(reconstructed)).to include('source' => 0)
    expect(boolish(row(reconstructed).fetch('current'))).to be(true)
    expect(row_count(:node_statuses)).to eq(1)
  end

  it 'advances the revision timestamp monotonically when the stored value is ahead of the clock' do
    future_updated_at = Time.now.utc + 1.day
    reconstructed = event(
      nil,
      source: 0,
      booted_at: timestamp - 1.minute,
      observed_before: timestamp + 1.minute,
      current: true
    )
    reported = event(
      evidence(booted_at: timestamp),
      observed_before: timestamp + 2.minutes,
      updated_at: future_updated_at
    )

    migrate_up!

    expect(find_rows(:node_kernel_events, { id: reconstructed })).to be_empty
    expect(row(reported)).to include(
      'confidence' => 2,
      'effective_at' => timestamp
    )
    expect(boolish(row(reported).fetch('current'))).to be(true)
    expect(row(reported).fetch('updated_at')).to be > future_updated_at
  end

  def evidence(booted_at:, snapshot_type: 1)
    insert_row(:node_kernel_evidences, snapshot_type:, booted_at:)
  end

  def event(
    evidence_id,
    node_id: 1,
    source_status_id: nil,
    event_type: 0,
    source: 1,
    confidence: 1,
    booted_at: timestamp,
    booted_release: '6.12.95',
    effective_at: nil,
    observed_after: nil,
    observed_before: timestamp + 3.minutes,
    current: false,
    updated_at: initial_event_timestamp
  )
    insert_row(
      :node_kernel_events,
      node_id:,
      node_kernel_evidence_id: evidence_id,
      source_status_id:,
      event_type:,
      source:,
      confidence:,
      booted_at:,
      booted_release:,
      effective_at:,
      observed_after:,
      observed_before:,
      current:,
      created_at: initial_event_timestamp,
      updated_at:
    )
  end

  def event_revision(event_id)
    event_row = row(event_id)
    event = Struct.new(:id, :updated_at, :kernel_evidence).new(
      event_row.fetch('id'),
      event_row.fetch('updated_at'),
      nil
    )
    VpsAdmin::API::KernelEvidence::Revision.event(event)
  end

  def current_collection_revision
    event_rows = rows(:node_kernel_events)
    relation = Struct.new(:event_rows) do
      def pick(*)
        [event_rows.length, event_rows.map { |event| event.fetch('updated_at') }.max]
      end
    end.new(event_rows)
    node = Struct.new(:node_kernel_events, :node_kernel_history_state).new(relation, nil)

    VpsAdmin::API::KernelEvidence::Revision.collection(node, nil)
  end

  def initial_event_timestamp
    timestamp - 1.day
  end

  def row(event_id)
    find_row(:node_kernel_events, id: event_id)
  end
end
