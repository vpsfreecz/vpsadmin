# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/queue/release'

RSpec.describe NodeCtld::Commands::Queue::Release do
  let(:driver) { build_storage_driver }

  it 'releases the queue and leaves rollback as a no-op' do
    cmd = described_class.new(driver, 'queue' => 'zfs_send')
    allow(cmd).to receive(:reserve_queue)
    allow(cmd).to receive(:release_queue)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:release_queue).with('zfs_send').once

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).not_to have_received(:reserve_queue)
    expect(cmd).to have_received(:release_queue).once
  end
end
