# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/rsync_dataset'

RSpec.describe NodeCtld::Commands::Dataset::RsyncDataset do
  let(:driver) { build_storage_driver }

  def build_command(allow_partial:)
    described_class.new(
      driver,
      'src_addr' => '192.0.2.10',
      'src_pool_fs' => 'tank/src',
      'dst_pool_name' => 'tank',
      'dst_pool_fs' => 'tank/dst',
      'dataset_name' => 'user.dataset',
      'allow_partial' => allow_partial
    )
  end

  it 'builds the expected rsync command' do
    cmd = build_command(allow_partial: false)

    allow(cmd).to receive(:syscmd).with(
      '/bin/rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after ' \
      '-e "ssh -i /tank/conf/send-receive/key -o StrictHostKeyChecking=no ' \
      '-o UserKnownHostsFile=/dev/null -l root" ' \
      '"192.0.2.10:/tank/src/user.dataset/private/" "/tank/dst/user.dataset/private/"',
      { valid_rcs: [0] }
    )

    $CFG = NodeCtldSpec::FakeCfg.new(bin: { rsync: '/bin/rsync' })
    cmd.exec
    expect(cmd).to have_received(:syscmd).with(
      '/bin/rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after ' \
      '-e "ssh -i /tank/conf/send-receive/key -o StrictHostKeyChecking=no ' \
      '-o UserKnownHostsFile=/dev/null -l root" ' \
      '"192.0.2.10:/tank/src/user.dataset/private/" "/tank/dst/user.dataset/private/"',
      { valid_rcs: [0] }
    )
  end

  it 'accepts partial rsync exit codes when allow_partial is true' do
    cmd = build_command(allow_partial: true)

    $CFG = NodeCtldSpec::FakeCfg.new(bin: { rsync: '/bin/rsync' })
    allow(cmd).to receive(:syscmd).with(
      include('rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after'),
      { valid_rcs: [23, 24] }
    )

    cmd.exec
    expect(cmd).to have_received(:syscmd).with(
      include('rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after'),
      { valid_rcs: [23, 24] }
    )
  end

  it 'rejects partial rsync exit codes when allow_partial is false' do
    cmd = build_command(allow_partial: false)

    $CFG = NodeCtldSpec::FakeCfg.new(bin: { rsync: '/bin/rsync' })
    allow(cmd).to receive(:syscmd).with(
      include('rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after'),
      { valid_rcs: [0] }
    )

    cmd.exec
    expect(cmd).to have_received(:syscmd).with(
      include('rsync -rlptgoxDHXA --numeric-ids --inplace --delete-after'),
      { valid_rcs: [0] }
    )
  end

  it 'has a no-op rollback' do
    expect(build_command(allow_partial: true).rollback).to eq(ret: :ok)
  end
end
