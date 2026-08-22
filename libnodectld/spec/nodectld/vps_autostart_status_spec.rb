# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/osctl_container'
require 'nodectld/vps_autostart_status'

RSpec.describe NodeCtld::VpsAutostartStatus do
  subject(:status) { described_class.new }

  def vps(id:, pool_fs: 'tank/vps', autostart: true)
    {
      'id' => id,
      'pool_fs' => pool_fs,
      'autostart_enable' => autostart
    }
  end

  def container(id:, pool: 'tank', state: 'running', autostart: true)
    NodeCtld::OsCtlContainer.new(
      id: id.to_s,
      pool:,
      state:,
      autostart:
    )
  end

  it 'reports every auto-start VPS that is not running' do
    snapshot = status.update(
      [
        vps(id: 101),
        vps(id: 102),
        vps(id: 103),
        vps(id: 104, autostart: false),
        vps(id: 201, pool_fs: 'archive/private')
      ],
      [
        container(id: 101),
        container(id: 102, state: 'starting'),
        container(id: 104),
        container(id: 201, pool: 'archive', state: 'stopped')
      ],
      now: Time.at(1_234)
    )

    expect(snapshot.success).to be(true)
    expect(snapshot.last_success_at).to eq(1_234)
    expect(snapshot.expected).to eq('tank' => 3, 'archive' => 1)
    expect(snapshot.unsatisfied.map { |vps| [vps.pool, vps.vps_id, vps.reason] })
      .to eq(
        [
          %w[archive 201 stopped],
          %w[tank 102 starting],
          %w[tank 103 missing]
        ]
      )
    expect(snapshot.unsatisfied_counts).to eq(
      %w[archive stopped] => 1,
      %w[tank starting] => 1,
      %w[tank missing] => 1
    )
  end

  it 'reports vpsAdmin and osctld auto-start setting differences' do
    snapshot = status.update(
      [
        vps(id: 101, autostart: true),
        vps(id: 102, autostart: false),
        vps(id: 103, autostart: false)
      ],
      [
        container(id: 101, autostart: false),
        container(id: 102, autostart: true),
        container(id: 103, autostart: false)
      ]
    )

    expect(
      snapshot.mismatches.map do |vps|
        [vps.vps_id, vps.vpsadmin, vps.osctld]
      end
    ).to eq(
      [
        %w[101 enabled disabled],
        %w[102 disabled enabled]
      ]
    )
  end

  it 'matches containers using both pool and VPS ID' do
    snapshot = status.update(
      [vps(id: 101, pool_fs: 'tank/private')],
      [container(id: 101, pool: 'archive')]
    )

    expect(snapshot.unsatisfied.first.reason).to eq('missing')
  end

  it 'rejects a non-empty response from an older vpsAdmin API' do
    expect do
      status.update(
        [{ 'id' => 101, 'pool_fs' => 'tank/private' }],
        []
      )
    end.to raise_error(
      described_class::UnsupportedResponse,
      /autostart_enable/
    )
  end

  it 'accepts an empty inventory response' do
    snapshot = status.update([], [], now: Time.at(1_234))

    expect(snapshot.success).to be(true)
    expect(snapshot.last_success_at).to eq(1_234)
    expect(snapshot.expected).to be_empty
  end

  it 'retains only freshness after a failed check' do
    successful = status.update(
      [vps(id: 101)],
      [container(id: 101, state: 'stopped')],
      now: Time.at(1_234)
    )
    failed = status.failed

    expect(failed.success).to be(false)
    expect(failed.last_success_at).to eq(successful.last_success_at)
    expect(failed.expected).to be_empty
    expect(failed.unsatisfied).to be_empty
    expect(failed.unsatisfied_counts).to be_empty
    expect(failed.mismatches).to be_empty
  end

  it 'publishes immutable snapshots' do
    snapshot = status.update([vps(id: 101)], [])

    expect(snapshot).to be_frozen
    expect(snapshot.expected).to be_frozen
    expect(snapshot.unsatisfied).to be_frozen
    expect(snapshot.unsatisfied.first).to be_frozen
    expect(snapshot.unsatisfied.first.pool).to be_frozen
    expect(snapshot.unsatisfied.first.vps_id).to be_frozen
    expect(snapshot.unsatisfied.first.reason).to be_frozen
    expect(snapshot.unsatisfied_counts.keys.first).to be_frozen
  end
end
