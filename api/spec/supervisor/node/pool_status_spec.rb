# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'VpsAdmin::Supervisor::Node::PoolStatus' do
  let(:node) { SpecSeed.node }
  let(:pool) { SpecSeed.pool }
  let(:other_pool) { SpecSeed.other_pool }
  let(:supervisor) { VpsAdmin::Supervisor::Node::PoolStatus.new(nil, node) }
  let(:status_time) { Time.utc(2026, 4, 2, 12, 0, 0) }

  describe '#update_pool_status' do
    it 'stores live space values in MiB and updates checked_at' do
      supervisor.send(
        :update_pool_status,
        {
          'id' => pool.id,
          'time' => status_time.to_i,
          'state' => 'online',
          'scan' => 'none',
          'scan_percent' => nil,
          'total_bytes' => 3 * 1024 * 1024 * 1024,
          'used_bytes' => 1025 * 1024 * 1024,
          'available_bytes' => 2047 * 1024 * 1024
        }
      )

      pool.reload
      expect(pool.state).to eq('online')
      expect(pool.scan).to eq('none')
      expect(pool.total_space).to eq(3072)
      expect(pool.used_space).to eq(1025)
      expect(pool.available_space).to eq(2047)
      expect(pool.checked_at).to eq(status_time)
    end

    it 'clears stale space values when the new fields are missing' do
      pool.update!(
        total_space: 1024,
        used_space: 512,
        available_space: 512
      )

      supervisor.send(
        :update_pool_status,
        {
          'id' => pool.id,
          'time' => status_time.to_i,
          'state' => 'degraded',
          'scan' => 'scrub',
          'scan_percent' => 35.5
        }
      )

      pool.reload
      expect(pool.state).to eq('degraded')
      expect(pool.scan).to eq('scrub')
      expect(pool.scan_percent).to eq(35.5)
      expect(pool.total_space).to be_nil
      expect(pool.used_space).to be_nil
      expect(pool.available_space).to be_nil
    end

    it 'does not update a pool on a different node' do
      other_pool.update!(
        state: :unknown,
        scan: :unknown,
        total_space: 128,
        used_space: 64,
        available_space: 64
      )

      supervisor.send(
        :update_pool_status,
        {
          'id' => other_pool.id,
          'time' => status_time.to_i,
          'state' => 'online',
          'scan' => 'none',
          'scan_percent' => nil,
          'total_bytes' => 2048 * 1024 * 1024,
          'used_bytes' => 1024 * 1024 * 1024,
          'available_bytes' => 1024 * 1024 * 1024
        }
      )

      other_pool.reload
      expect(other_pool.state).to eq('unknown')
      expect(other_pool.scan).to eq('unknown')
      expect(other_pool.total_space).to eq(128)
      expect(other_pool.used_space).to eq(64)
      expect(other_pool.available_space).to eq(64)
    end
  end
end
