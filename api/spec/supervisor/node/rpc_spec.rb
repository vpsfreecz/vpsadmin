# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe 'VpsAdmin::Supervisor::Node::Rpc::Handler' do
  let(:node) { SpecSeed.node }
  let(:user) { SpecSeed.user }
  let(:handler) { VpsAdmin::Supervisor::Node::Rpc::Handler.new(node) }

  before do
    SpecSeed.user
    SpecSeed.node
    SpecSeed.pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def create_vps!(dataset_in_pool:)
    Vps.create!(
      user: user,
      node: node,
      hostname: "spec-vps-#{SecureRandom.hex(4)}",
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active,
      confirmed: :confirmed
    )
  end

  describe '#list_vps_status_check' do
    it 'skips vpses with a missing dataset_in_pool' do
      _, valid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "status-good-#{SecureRandom.hex(4)}"
      )
      _, invalid_dip = create_dataset_with_pool!(
        user: user,
        pool: SpecSeed.pool,
        name: "status-bad-#{SecureRandom.hex(4)}"
      )

      valid_vps = create_vps!(dataset_in_pool: valid_dip)
      invalid_vps = create_vps!(dataset_in_pool: invalid_dip)
      invalid_vps.update_column(:dataset_in_pool_id, nil)
      result = nil

      expect do
        result = handler.list_vps_status_check
      end.not_to raise_error

      expect(result).to contain_exactly(
        {
          id: valid_vps.id,
          read_hostname: false,
          pool_fs: SpecSeed.pool.filesystem
        }
      )
    end
  end
end
