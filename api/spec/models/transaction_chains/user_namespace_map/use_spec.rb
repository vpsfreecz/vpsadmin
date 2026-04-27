# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::UserNamespaceMap::Use do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  it 'emits a UseMap transaction with pool, map, UID/GID, node, and VPS parameters' do
    user = create_lifecycle_user!
    fixture = build_standalone_vps_fixture(user: user)
    _userns, map = create_user_namespace_with_map!(user: user)
    vps = fixture.fetch(:vps)
    vps.update!(user_namespace_map: map)

    chain, = described_class.fire(vps, map)
    transactions = transactions_for(chain)
    tx = transactions.fetch(0)
    payload = tx_payload(chain, Transactions::UserNamespace::UseMap)

    expect(transactions.size).to eq(1)
    expect(Transaction.for_type(tx.handle)).to eq(Transactions::UserNamespace::UseMap)
    expect(tx.node_id).to eq(vps.node_id)
    expect(tx.vps_id).to eq(vps.id)
    expect(payload).to include(
      'pool_fs' => fixture.fetch(:pool).filesystem,
      'name' => map.id.to_s,
      'uidmap' => map.build_map(:uid),
      'gidmap' => map.build_map(:gid)
    )
  end
end
