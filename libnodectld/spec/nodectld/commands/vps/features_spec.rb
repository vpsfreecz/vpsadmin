# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/features'

RSpec.describe NodeCtld::Commands::Vps::Features do
  let(:driver) { build_vps_driver }

  def feature_state(enabled:, original:)
    { 'enabled' => enabled, 'original' => original }
  end

  def build_features(overrides = {})
    {
      'tun' => feature_state(enabled: true, original: false),
      'fuse' => feature_state(enabled: false, original: true),
      'ppp' => feature_state(enabled: false, original: false),
      'kvm' => feature_state(enabled: true, original: false),
      'lxc' => feature_state(enabled: true, original: false),
      'impermanence' => feature_state(enabled: true, original: false)
    }.merge(overrides)
  end

  it 'applies device, nesting, and impermanence changes and restarts running VPSes' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'features' => build_features
    )

    allow(cmd).to receive_messages(osctl: { ret: :ok }, status: :running)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct devices add],
      [101, 'char', '10', '200', 'rwm', '/dev/net/tun'],
      parents: true
    )
    expect(cmd).to have_received(:osctl).with(
      %i[ct devices del],
      [101, 'char', '10', '229'],
      {},
      {},
      valid_rcs: [1]
    )
    expect(cmd).to have_received(:osctl).with(
      %i[ct devices add],
      [101, 'char', '10', '232', 'rwm', '/dev/kvm'],
      parents: true
    )
    expect(cmd).to have_received(:osctl).with(%i[ct set nesting], 101)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set impermanence],
      101,
      { zfs_property: 'refquota=10G' }
    )
    expect(cmd).to have_received(:osctl).with(%i[ct restart], 101)
  end

  it 'ignores already-existing device errors while enabling device access' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'features' => build_features(
        'fuse' => feature_state(enabled: false, original: false),
        'kvm' => feature_state(enabled: false, original: false),
        'lxc' => feature_state(enabled: false, original: false),
        'impermanence' => feature_state(enabled: false, original: false)
      )
    )

    allow(cmd).to receive_messages(osctl: { ret: :ok }, status: :stopped)
    allow(cmd).to receive(:osctl).with(
      %i[ct devices add],
      [101, 'char', '10', '200', 'rwm', '/dev/net/tun'],
      parents: true
    ).and_raise(system_command_failed('osctl', rc: 1, output: 'error: device already exists'))

    expect { cmd.exec }.not_to raise_error
  end

  it 'restores original feature state without restarting stopped VPSes' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'features' => build_features
    )

    allow(cmd).to receive_messages(osctl: { ret: :ok }, status: :stopped)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct devices del],
      [101, 'char', '10', '200'],
      {},
      {},
      valid_rcs: [1]
    )
    expect(cmd).to have_received(:osctl).with(
      %i[ct devices add],
      [101, 'char', '10', '229', 'rwm', '/dev/fuse'],
      parents: true
    )
    expect(cmd).to have_received(:osctl).with(%i[ct unset nesting], 101)
    expect(cmd).to have_received(:osctl).with(%i[ct unset impermanence], 101)
    expect(cmd).not_to have_received(:osctl).with(%i[ct restart], 101)
  end
end
