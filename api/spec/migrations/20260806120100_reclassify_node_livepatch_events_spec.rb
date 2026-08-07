# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260806120100_reclassify_node_livepatch_events')

RSpec.describe ReclassifyNodeLivepatchEvents do
  before do
    define_schema do
      create_table :node_kernel_evidences do |t|
        t.bigint :node_id, null: false
      end

      create_table :node_kernel_livepatches do |t|
        t.bigint :node_kernel_evidence_id, null: false
        t.string :livepatch_id, null: false
        t.boolean :loaded
        t.boolean :enabled
        t.boolean :transition
        t.datetime :applied_at
        t.datetime :verified_at
      end

      create_table :node_software_versions do |t|
        t.bigint :node_kernel_evidence_id, null: false
        t.integer :generation, null: false
        t.integer :component, null: false
        t.string :revision
      end

      create_table :node_kernel_events do |t|
        t.bigint :node_id, null: false
        t.bigint :node_kernel_evidence_id
        t.integer :event_type, null: false
        t.integer :source, null: false
        t.integer :confidence, null: false
        t.integer :livepatch_action
        t.string :reported_release, null: false
        t.datetime :effective_at
        t.datetime :observed_before, null: false
        t.boolean :current, null: false, default: false
        t.timestamps null: false
      end
    end
  end

  it 'reclassifies only safe inventory rows and backfills observed applications' do
    boot_evidence = evidence(node_id: 1)
    boot = event(
      node_id: 1,
      evidence_id: boot_evidence,
      event_type: 0,
      current: false,
      observed_before: timestamp
    )
    inventory_evidence = evidence(node_id: 1)
    livepatch(inventory_evidence, loaded: false, enabled: false, transition: false)
    inventory = event(
      node_id: 1,
      evidence_id: inventory_evidence,
      current: true,
      observed_before: timestamp + 1.minute
    )

    legacy_evidence = evidence(node_id: 2)
    livepatch(
      legacy_evidence,
      loaded: true,
      enabled: true,
      transition: false,
      applied_at: timestamp + 2.minutes
    )
    legacy = event(
      node_id: 2,
      evidence_id: legacy_evidence,
      effective_at: timestamp + 2.minutes
    )

    ambiguous_evidence = evidence(node_id: 4)
    ambiguous = event(node_id: 4, evidence_id: ambiguous_evidence)

    migrate_up!

    expect(row(inventory)).to include(
      'event_type' => 7,
      'livepatch_action' => nil
    )
    expect(boolish(row(inventory).fetch('current'))).to be(false)
    expect(boolish(row(boot).fetch('current'))).to be(true)
    expect(row(legacy)).to include(
      'livepatch_action' => 0,
      'effective_at' => nil,
      'confidence' => 1
    )
    expect(row(ambiguous)).to include(
      'event_type' => 2,
      'livepatch_action' => nil
    )
    expect(row_count(:node_kernel_livepatches)).to eq(2)
  end

  it 'does not reinterpret an empty snapshot that may represent removal' do
    event(node_id: 5, event_type: 0, observed_before: timestamp)
    removal_evidence = evidence(node_id: 5)
    removal = event(
      node_id: 5,
      evidence_id: removal_evidence,
      current: true,
      observed_before: timestamp + 1.minute
    )

    migrate_up!

    expect(row(removal)).to include(
      'event_type' => 2,
      'livepatch_action' => nil
    )
    expect(boolish(row(removal).fetch('current'))).to be(true)
  end

  it 'does not reinterpret an all-false snapshot for the effective patch' do
    stable_evidence = evidence(node_id: 7)
    livepatch(
      stable_evidence,
      livepatch_id: 'livepatch_2',
      loaded: true,
      enabled: true,
      transition: false,
      applied_at: timestamp
    )
    event(
      node_id: 7,
      evidence_id: stable_evidence,
      event_type: 0,
      observed_before: timestamp
    )
    software_version(stable_evidence, revision: 'f' * 40)
    removal_evidence = evidence(node_id: 7)
    livepatch(
      removal_evidence,
      livepatch_id: 'livepatch_2',
      loaded: false,
      enabled: false,
      transition: false
    )
    removal = event(
      node_id: 7,
      evidence_id: removal_evidence,
      current: true,
      observed_before: timestamp + 1.minute
    )
    software_version(removal_evidence, revision: 'a' * 40)
    software_rows = rows(:node_software_versions)

    migrate_up!

    expect(row(removal)).to include(
      'event_type' => 2,
      'livepatch_action' => nil
    )
    expect(boolish(row(removal).fetch('current'))).to be(true)
    expect(rows(:node_software_versions)).to eq(software_rows)
  end

  it 'reclassifies an unavailable successor while the effective patch remains reported' do
    application_evidence = evidence(node_id: 6)
    livepatch(
      application_evidence,
      livepatch_id: 'livepatch_2',
      loaded: true,
      enabled: true,
      transition: false,
      applied_at: timestamp
    )
    application = event(
      node_id: 6,
      evidence_id: application_evidence,
      event_type: 0,
      reported_release: '6.12.95.2',
      observed_before: timestamp
    )
    unavailable_evidence = evidence(node_id: 6)
    livepatch(
      unavailable_evidence,
      livepatch_id: 'livepatch_3',
      loaded: false,
      enabled: false,
      transition: false
    )
    unavailable = event(
      node_id: 6,
      evidence_id: unavailable_evidence,
      reported_release: '6.12.95.2',
      current: true,
      observed_before: timestamp + 1.minute
    )

    migrate_up!

    expect(row(unavailable)).to include(
      'event_type' => 7,
      'livepatch_action' => nil
    )
    expect(boolish(row(unavailable).fetch('current'))).to be(false)
    expect(boolish(row(application).fetch('current'))).to be(true)
  end

  it 'keeps a later rollback boot current and preserves older software revisions' do
    initial_evidence = evidence(node_id: 8)
    event(
      node_id: 8,
      evidence_id: initial_evidence,
      event_type: 0,
      reported_release: '6.12.95',
      observed_before: timestamp
    )

    application_evidence = evidence(node_id: 8)
    livepatch(
      application_evidence,
      livepatch_id: 'livepatch_2',
      loaded: true,
      enabled: true,
      transition: false,
      applied_at: timestamp + 1.minute
    )
    application = event(
      node_id: 8,
      evidence_id: application_evidence,
      effective_at: timestamp + 1.minute,
      reported_release: '6.12.95.2',
      observed_before: timestamp + 2.minutes
    )
    software_version(application_evidence, revision: 'f' * 40)

    unavailable_evidence = evidence(node_id: 8)
    livepatch(
      unavailable_evidence,
      livepatch_id: 'livepatch_3',
      loaded: false,
      enabled: false,
      transition: false
    )
    unavailable = event(
      node_id: 8,
      evidence_id: unavailable_evidence,
      reported_release: '6.12.95.2',
      observed_before: timestamp + 3.minutes
    )

    rollback_evidence = evidence(node_id: 8)
    rollback = event(
      node_id: 8,
      evidence_id: rollback_evidence,
      event_type: 0,
      current: true,
      reported_release: '6.12.95',
      observed_before: timestamp + 4.minutes
    )
    software_version(rollback_evidence, revision: 'a' * 40)
    software_rows = rows(:node_software_versions)

    migrate_up!

    expect(row(application)).to include(
      'event_type' => 2,
      'livepatch_action' => 0,
      'effective_at' => nil,
      'confidence' => 1
    )
    expect(boolish(row(application).fetch('current'))).to be(false)
    expect(row(unavailable)).to include(
      'event_type' => 7,
      'livepatch_action' => nil
    )
    expect(boolish(row(unavailable).fetch('current'))).to be(false)
    expect(row(rollback).fetch('event_type')).to eq(0)
    expect(boolish(row(rollback).fetch('current'))).to be(true)
    expect(rows(:node_kernel_events).count { |event_row| boolish(event_row.fetch('current')) }).to eq(1)
    expect(rows(:node_software_versions)).to eq(software_rows)
  end

  it 'keeps corrected classifications on rollback' do
    boot_evidence = evidence(node_id: 1)
    event(
      node_id: 1,
      evidence_id: boot_evidence,
      event_type: 0,
      observed_before: timestamp
    )
    inventory_evidence = evidence(node_id: 1)
    livepatch(inventory_evidence, loaded: false, enabled: false, transition: false)
    inventory = event(
      node_id: 1,
      evidence_id: inventory_evidence,
      current: true,
      observed_before: timestamp + 1.minute
    )

    migrate_up!
    corrected = row(inventory)
    migrate_down!

    expect(row(inventory)).to eq(corrected)
  end

  def evidence(node_id:)
    insert_row(:node_kernel_evidences, node_id:)
  end

  def livepatch(evidence_id, **attrs)
    insert_row(
      :node_kernel_livepatches,
      {
        node_kernel_evidence_id: evidence_id,
        livepatch_id: "livepatch_#{evidence_id}",
        loaded: nil,
        enabled: nil,
        transition: nil,
        applied_at: nil,
        verified_at: nil
      }.merge(attrs)
    )
  end

  def event(
    node_id:,
    evidence_id: nil,
    event_type: 2,
    effective_at: nil,
    observed_before: timestamp + 5.minutes,
    current: false,
    reported_release: '6.12.95'
  )
    insert_row(
      :node_kernel_events,
      node_id:,
      node_kernel_evidence_id: evidence_id,
      event_type:,
      source: 1,
      confidence: effective_at ? 2 : 1,
      livepatch_action: nil,
      reported_release:,
      effective_at:,
      observed_before:,
      current:,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def software_version(evidence_id, revision:)
    insert_row(
      :node_software_versions,
      node_kernel_evidence_id: evidence_id,
      generation: 1,
      component: 0,
      revision:
    )
  end

  def row(id)
    find_row(:node_kernel_events, id:)
  end
end
