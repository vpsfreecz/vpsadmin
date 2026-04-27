# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/queue/reserve'

RSpec.describe NodeCtld::Commands::Queue::Reserve do
  let(:driver) { build_storage_driver }

  it 'reserves the queue and releases it on rollback' do
    cmd = described_class.new(driver, 'queue' => 'zfs_send')
    allow(cmd).to receive(:reserve_queue)
    allow(cmd).to receive(:release_queue)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:reserve_queue).with('zfs_send')

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:release_queue).with('zfs_send')
  end
end
