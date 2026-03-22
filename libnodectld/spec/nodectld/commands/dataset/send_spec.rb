# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/send'
require 'nodectld/zfs_stream'

RSpec.describe NodeCtld::Commands::Dataset::Send do
  let(:driver) do
    instance_double(
      NodeCtld::Command,
      id: 123,
      progress: nil,
      'progress=': nil,
      log_type: :spec
    )
  end

  let(:db) { instance_double(NodeCtld::Db, close: nil) }
  let(:stream) { instance_double(NodeCtld::ZfsStream) }

  before do
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(NodeCtld::ZfsStream).to receive(:new).and_return(stream)
    allow(stream).to receive(:command).and_yield
    allow(stream).to receive(:send_to)
  end

  def install_mbuffer_cfg(send_command: 'mbuffer')
    $CFG = NodeCtldSpec::FakeCfg.new(
      mbuffer: {
        send: {
          command: send_command,
          block_size: '1M',
          buffer_size: '256M',
          timeout: 5
        }
      }
    )
  end

  def build_command(snapshots)
    described_class.new(
      driver,
      'addr' => '127.0.0.1',
      'port' => 39_001,
      'src_pool_fs' => 'tank/ct',
      'dataset_name' => '101',
      'tree' => 'tree.0',
      'branch' => 'branch-2024-01-01.0',
      'snapshots' => snapshots
    )
  end

  it 'uses the configured send mbuffer command during exec' do
    install_mbuffer_cfg(send_command: '/run/test/faulty-mbuffer')

    cmd = build_command(
      [
        { 'id' => 1, 'confirmed' => 'confirmed', 'name' => 'snap-base' },
        { 'id' => 2, 'confirmed' => 'confirmed', 'name' => 'snap-new' }
      ]
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(stream).to have_received(:send_to).with(
      '127.0.0.1',
      39_001,
      command: '/run/test/faulty-mbuffer',
      block_size: '1M',
      buffer_size: '256M',
      log_file: kind_of(String),
      timeout: 5
    )
  end
end
