# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe Transactions::Vps::PopulateConfig do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:node) { SpecSeed.node }
  let(:user) { SpecSeed.user }

  def build_vps_fixture!
    pool = create_pool!(node: node, role: :hypervisor)
    _, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "rootfs-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: node, dataset_in_pool: dip)
    [vps, pool]
  end

  it 'uses the VPS pool by default' do
    vps, pool = build_vps_fixture!

    tx = described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: [vps]
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('pool_fs')).to eq(pool.filesystem)
  end

  it 'allows callers to override the target pool' do
    vps, _src_pool = build_vps_fixture!
    dst_pool = create_pool!(
      node: node,
      role: :hypervisor,
      filesystem: "dst-#{SecureRandom.hex(4)}"
    )

    tx = described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: [vps],
      kwargs: { pool: dst_pool }
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('pool_fs')).to eq(dst_pool.filesystem)
  end
end
