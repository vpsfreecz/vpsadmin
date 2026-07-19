# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe VpsAdmin::API::Tasks::NodeHistoryBackfill do
  let(:node) { SpecSeed.node }
  let(:output) { StringIO.new }
  let(:env) { { 'NODE_ID' => node.id.to_s } }
  let(:task) { described_class.new(io: output, env:) }

  def kernel_operation = VpsAdmin::API::Operations::Node::ReconstructKernelEvents
  def system_operation = VpsAdmin::API::Operations::Node::ReconstructSystemStates

  before do
    node.node_kernel_history_state&.destroy!
    node.node_system_history_state&.destroy!
    allow(kernel_operation).to receive(:run).and_return(1)
    allow(system_operation).to receive(:run).and_return(2)
  end

  it 'runs both components for the selected Node with the default batch size' do
    expect(task.reconstruct).to eq(3)

    expect(kernel_operation).to have_received(:run).with(
      node,
      batch_size: 10_000,
      force: false,
      progress: kind_of(VpsAdmin::API::Tasks::ProgressReporter)
    )
    expect(system_operation).to have_received(:run).with(
      node,
      batch_size: 10_000,
      force: false,
      progress: kind_of(VpsAdmin::API::Tasks::ProgressReporter)
    )
    expect(output.string).to include(
      "node=#{node.id}/#{node.domain_name} overall=pending " \
      'kernel=pending kernel_completed_at=- kernel_status_ids=-'
    )
  end

  it 'processes every pending eligible Node when NODE_ID is omitted' do
    all_task = described_class.new(io: output, env: {})
    allow(all_task).to receive(:eligible_nodes).and_return([node])

    expect(all_task.reconstruct(components: [:kernel])).to eq(1)
    expect(kernel_operation).to have_received(:run).with(
      node,
      hash_including(batch_size: 10_000, force: false)
    )
  end

  it 'prints completion timestamps and boundaries after reconstruction' do
    completed_at = Time.utc(2026, 7, 19, 12, 0, 0)
    allow(kernel_operation).to receive(:run) do |selected, **|
      NodeKernelHistoryState.create!(
        node: selected,
        from_status_id: 10,
        through_status_id: 20,
        started_at: completed_at - 1.hour,
        observed_through: completed_at - 1.minute,
        completed_at:
      )
      1
    end
    allow(system_operation).to receive(:run) do |selected, **|
      NodeSystemHistoryState.create!(
        node: selected,
        from_status_id: 11,
        through_status_id: 21,
        started_at: completed_at - 30.minutes,
        observed_through: completed_at,
        completed_at:
      )
      2
    end

    expect(task.reconstruct).to eq(3)

    expect(output.string).to include(
      "node=#{node.id}/#{node.domain_name} overall=complete " \
      'kernel=complete kernel_completed_at=2026-07-19T12:00:00.000000Z ' \
      'kernel_status_ids=10..20'
    )
    expect(output.string).to include(
      'system=complete system_completed_at=2026-07-19T12:00:00.000000Z ' \
      'system_status_ids=11..21'
    )
  end

  it 'rejects malformed and missing Node IDs before reconstruction' do
    invalid = described_class.new(io: output, env: { 'NODE_ID' => 'invalid' })
    missing = described_class.new(io: output, env: { 'NODE_ID' => '999999999' })

    expect { invalid.reconstruct }.to raise_error(ArgumentError, /NODE_ID must be a positive integer/)
    expect { missing.reconstruct }.to raise_error(ArgumentError, /does not exist/)
    expect(kernel_operation).not_to have_received(:run)
    expect(system_operation).not_to have_received(:run)
  end

  it 'rejects service-only Node roles before reconstruction' do
    node.update!(role: :mailer)

    expect { task.reconstruct }.to raise_error(ArgumentError, /service-only role mailer/)
    expect(kernel_operation).not_to have_received(:run)
    expect(system_operation).not_to have_received(:run)
  ensure
    node.update!(role: :node)
  end

  it 'resumes only the missing component of a partial combined run' do
    NodeKernelHistoryState.create!(node:, completed_at: Time.current)

    expect(task.reconstruct).to eq(2)
    expect(kernel_operation).not_to have_received(:run)
    expect(system_operation).to have_received(:run).once
  end

  it 'reruns completed components with FORCE=1' do
    NodeKernelHistoryState.create!(node:, completed_at: Time.current)
    NodeSystemHistoryState.create!(node:, completed_at: Time.current)
    forced = described_class.new(io: output, env: env.merge('FORCE' => '1'))

    expect(forced.reconstruct).to eq(3)
    expect(kernel_operation).to have_received(:run).with(node, hash_including(force: true))
    expect(system_operation).to have_received(:run).with(node, hash_including(force: true))
  end

  it 'validates BATCH_SIZE before reconstruction' do
    zero = described_class.new(io: output, env: env.merge('BATCH_SIZE' => '0'))
    text = described_class.new(io: output, env: env.merge('BATCH_SIZE' => 'many'))

    expect { zero.reconstruct }.to raise_error(ArgumentError, /BATCH_SIZE must be a positive integer/)
    expect { text.reconstruct }.to raise_error(ArgumentError, /BATCH_SIZE must be a positive integer/)
    expect(kernel_operation).not_to have_received(:run)
    expect(system_operation).not_to have_received(:run)
  end

  it 'prints per-component checkpoints and partial status summaries' do
    completed_at = Time.utc(2026, 7, 19, 12, 0, 0)
    NodeKernelHistoryState.create!(
      node:,
      from_status_id: 10,
      through_status_id: 20,
      started_at: completed_at - 1.hour,
      observed_through: completed_at - 1.minute,
      completed_at:
    )
    node.update!(active: false)

    task.status

    expect(output.string).to include("ID\tNAME\tROLE\tACTIVE\tOVERALL")
    expect(output.string).to include(
      "#{node.id}\t#{node.domain_name}\tnode\tno\tpartial\tcomplete"
    )
    expect(output.string).to include('10..20')
    expect(output.string).to include('2026-07-19T12:00:00.000000Z')
    expect(output.string).to include(
      'Status history backfill totals: pending=0 partial=1 complete=0 total=1'
    )
  ensure
    node.update!(active: true)
  end

  it 'reports zero pending work without invoking reconstruction' do
    completed_at = Time.utc(2026, 7, 19, 12, 0, 0)
    NodeKernelHistoryState.create!(
      node:,
      from_status_id: 10,
      through_status_id: 20,
      started_at: completed_at - 1.hour,
      observed_through: completed_at - 1.minute,
      completed_at:
    )
    NodeSystemHistoryState.create!(
      node:,
      from_status_id: 11,
      through_status_id: 21,
      started_at: completed_at - 30.minutes,
      observed_through: completed_at,
      completed_at:
    )

    expect(task.reconstruct).to eq(0)

    expect(output.string).to include('No pending combined history backfills')
    expect(output.string).to include(
      "node=#{node.id}/#{node.domain_name} overall=complete " \
      'kernel=complete kernel_completed_at=2026-07-19T12:00:00.000000Z ' \
      'kernel_status_ids=10..20'
    )
    expect(output.string).to include(
      'system=complete system_completed_at=2026-07-19T12:00:00.000000Z ' \
      'system_status_ids=11..21'
    )
    expect(output.string).to include(
      'Before history backfill totals: pending=1 partial=0 complete=1 total=2'
    )
    expect(kernel_operation).not_to have_received(:run)
    expect(system_operation).not_to have_received(:run)
  end

  it 'leaves a partial checkpoint when the second component fails' do
    allow(kernel_operation).to receive(:run) do |selected, **|
      NodeKernelHistoryState.create!(node: selected, completed_at: Time.current)
      1
    end
    allow(system_operation).to receive(:run).and_raise('system failed')

    expect { task.reconstruct }.to raise_error('system failed')

    expect(node.reload.node_kernel_history_state).to be_present
    expect(node.node_system_history_state).to be_nil
    expect(output.string).to include(
      'After history backfill totals: pending=1 partial=1 complete=0 total=2'
    )
    expect(output.string).to include(
      "node=#{node.id}/#{node.domain_name} overall=partial kernel=complete"
    )
  end
end
