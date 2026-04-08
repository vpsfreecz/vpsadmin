# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Mount do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'queues a single mount transaction with the supplied mount rows and no DB side effects' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'mount-chain')
    vps = fixture.fetch(:vps)
    _subdataset, sub_dip = create_vps_subdataset!(
      user: user,
      pool: fixture.fetch(:pool),
      parent: fixture.fetch(:dataset)
    )
    mount = create_mount_record!(vps: vps, dataset_in_pool: sub_dip, dst: '/mnt/data')

    chain, = described_class.fire(vps, [mount])

    expect(tx_classes(chain)).to eq([Transactions::Vps::Mount])
    expect(tx_payload(chain, Transactions::Vps::Mount)).to include(
      'pool_fs' => fixture.fetch(:pool).filesystem,
      'mounts' => [
        include(
          'id' => mount.id,
          'dataset_name' => sub_dip.dataset.full_name,
          'dst' => '/mnt/data',
          'mode' => 'rw'
        )
      ]
    )
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Vps', vps.id])
    expect(confirmations_for(chain)).to eq([])
  end
end
