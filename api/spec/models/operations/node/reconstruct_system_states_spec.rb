# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Node::ReconstructSystemStates do
  let(:node) { SpecSeed.node }
  let(:base_time) { Time.utc(2026, 7, 16, 10, 0, 0) }

  def status!(at:, cpus:, memory:, swap:, cgroup: :cgroup_v2)
    NodeStatus.create!(
      node:,
      created_at: at,
      uptime: 100,
      vpsadmin_version: 'spec',
      kernel: '6.12.0',
      cpus:,
      total_memory: memory,
      total_swap: swap,
      cgroup_version: cgroup
    )
  end

  before do
    node.node_system_states.delete_all
    node.node_statuses.delete_all
    node.node_current_status&.destroy!
    node.node_system_history_state&.destroy!
  end

  it 'collapses historical samples and appends current status' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    status!(at: base_time + 15.minutes, cpus: 4, memory: 4096, swap: 0)
    status!(at: base_time + 30.minutes, cpus: 8, memory: 8192, swap: 1024)
    NodeCurrentStatus.create!(
      node:,
      created_at: base_time + 40.minutes,
      updated_at: base_time + 45.minutes,
      update_count: 1,
      vpsadmin_version: 'spec',
      cpus: 8,
      total_memory: 8192,
      total_swap: 1024,
      cgroup_version: :cgroup_v2
    )

    expect(described_class.run(node, batch_size: 1)).to eq(2)

    states = node.node_system_states.order(:first_observed_at).to_a
    expect(states.length).to eq(2)
    expect(states.first.attributes.symbolize_keys).to include(
      cpus: 4,
      total_memory: 4096,
      total_swap: 0,
      first_observed_at: base_time,
      last_observed_at: base_time + 15.minutes,
      current: false
    )
    expect(states.last.attributes.symbolize_keys).to include(
      cpus: 8,
      first_observed_at: base_time + 30.minutes,
      last_observed_at: base_time + 45.minutes,
      current: true
    )
    checkpoint = node.reload.node_system_history_state
    expect(checkpoint.from_status_id).to eq(node.node_statuses.order(:created_at, :id).first.id)
    expect(checkpoint.through_status_id).to eq(node.node_statuses.order(:created_at, :id).last.id)
    expect(checkpoint.observed_through).to eq(base_time + 45.minutes)
  end

  it 'preserves unknown legacy values and is idempotent' do
    status!(at: base_time, cpus: nil, memory: nil, swap: nil, cgroup: :cgroup_invalid)

    expect(described_class.run(node, batch_size: 1)).to eq(1)
    ids = node.node_system_states.ids

    expect(described_class.run(node)).to eq(0)
    expect(node.node_system_states.ids).to eq(ids)
    expect(node.node_system_states.sole).to have_attributes(
      cpus: nil,
      total_memory: nil,
      total_swap: nil,
      cgroup_version: 'cgroup_invalid'
    )
  end

  it 'prepends history without replacing states recorded by live ingestion' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    live = node.node_system_states.create!(
      cpus: 8,
      total_memory: 8192,
      total_swap: 1024,
      cgroup_version: :cgroup_v2,
      first_observed_at: base_time + 30.minutes,
      last_observed_at: base_time + 45.minutes,
      current: true
    )

    expect(described_class.run(node, batch_size: 1)).to eq(1)

    expect(node.node_system_states.order(:first_observed_at).last).to eq(live)
    expect(live.reload).to be_current
  end

  it 'does not store history for service roles' do
    node.update!(role: :mailer)
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)

    expect(described_class.run(node)).to eq(0)
    expect(node.node_system_states).to be_empty
  ensure
    node.update!(role: :node)
  end

  it 'keeps a live state current while merging an equal run across batches' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    status!(at: base_time + 10.minutes, cpus: 8, memory: 8192, swap: 1024)
    status!(at: base_time + 20.minutes, cpus: 8, memory: 8192, swap: 1024)
    live = node.node_system_states.create!(
      cpus: 8,
      total_memory: 8192,
      total_swap: 1024,
      cgroup_version: :cgroup_v2,
      first_observed_at: base_time + 30.minutes,
      last_observed_at: base_time + 40.minutes,
      current: true
    )

    expect(described_class.run(node, batch_size: 1)).to eq(1)

    expect(live.reload).to have_attributes(
      first_observed_at: base_time + 10.minutes,
      last_observed_at: base_time + 40.minutes,
      current: true
    )
    expect(node.node_system_states.where(current: true)).to contain_exactly(live)
  end

  it 'reruns completed reconstruction only when forced without duplicating states' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    status!(at: base_time + 10.minutes, cpus: 8, memory: 8192, swap: 1024)
    described_class.run(node, batch_size: 1)
    first_completed_at = node.reload.node_system_history_state.completed_at

    expect(described_class.run(node)).to eq(0)
    expect(node.node_system_states.count).to eq(2)

    expect(described_class.run(node, force: true, batch_size: 1)).to eq(2)
    expect(node.node_system_states.count).to eq(2)
    expect(node.node_system_states.current.count).to eq(1)
    expect(node.reload.node_system_history_state.completed_at).to be >= first_completed_at
  end

  it 'preserves live transitions when forcing an initially empty completion' do
    expect(described_class.run(node)).to eq(0)
    expect(node.reload.node_system_history_state.observed_through).to be_nil

    first_live = node.node_system_states.create!(
      cpus: 4,
      total_memory: 4096,
      total_swap: 0,
      cgroup_version: :cgroup_v2,
      first_observed_at: base_time,
      last_observed_at: base_time + 10.minutes,
      current: false
    )
    current_live = node.node_system_states.create!(
      cpus: 8,
      total_memory: 8192,
      total_swap: 1024,
      cgroup_version: :cgroup_v2,
      first_observed_at: base_time + 20.minutes,
      last_observed_at: base_time + 30.minutes,
      current: true
    )

    expect(described_class.run(node, force: true, batch_size: 1)).to eq(0)

    expect(node.node_system_states.order(:first_observed_at)).to eq([first_live, current_live])
    expect(first_live.reload).to have_attributes(
      first_observed_at: base_time,
      last_observed_at: base_time + 10.minutes,
      current: false
    )
    expect(current_live.reload).to have_attributes(
      first_observed_at: base_time + 20.minutes,
      last_observed_at: base_time + 30.minutes,
      current: true
    )
  end

  it 'rolls back states when the completion checkpoint cannot be written' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    checkpoint = NodeSystemHistoryState.new(node:)
    allow(NodeSystemHistoryState).to receive(:new).and_return(checkpoint)
    allow(checkpoint).to receive(:save!).and_raise('checkpoint failed')

    expect { described_class.run(node) }.to raise_error('checkpoint failed')
    expect(node.node_system_states.reload).to be_empty
    expect(NodeSystemHistoryState.where(node:)).to be_empty
  end

  it 'retries an unlocked scan and reconciles a concurrently ingested live state' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    status!(at: base_time + 20.minutes, cpus: 8, memory: 8192, swap: 1024)
    live = nil
    progress = Object.new
    allow(progress).to receive(:start)
    allow(progress).to receive(:finish)
    allow(progress).to receive(:retry)
    allow(progress).to receive(:advance) do
      next if live

      live = node.node_system_states.create!(
        cpus: 8,
        total_memory: 8192,
        total_swap: 1024,
        cgroup_version: :cgroup_v2,
        first_observed_at: base_time + 15.minutes,
        last_observed_at: base_time + 15.minutes,
        current: true
      )
    end

    expect(described_class.run(node, batch_size: 1, progress:)).to eq(1)

    expect(progress).to have_received(:retry).once
    expect(live.reload).to be_current
    expect(node.node_system_states.where(current: true)).to contain_exactly(live)
    expect(node.node_system_states.order(:first_observed_at).pluck(:cpus)).to eq([4, 8])
  end

  it 'does not instantiate full status records and plucks only system columns' do
    status!(at: base_time, cpus: 4, memory: 4096, swap: 0)
    sql = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql << payload[:sql] if payload[:sql].include?('node_statuses')
    end
    allow(NodeStatus).to receive(:instantiate).and_raise('full status materialized')

    described_class.run(node, batch_size: 1)

    data_query = sql.find do |query|
      query.include?('created_at') && query.include?('cpus') && query.include?('total_memory')
    end
    expect(data_query).to be_present
    expect(data_query).not_to include('uptime', 'kernel', 'vpsadmin_version')
    expect(sql).not_to include(a_string_matching(/node_statuses\.\*/i))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
