# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::UserNamespaceMap::Disuse do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def create_vps_with_namespace_map
    user = create_lifecycle_user!
    fixture = build_standalone_vps_fixture(user: user)
    _userns, map = create_user_namespace_with_map!(user: user)
    vps = fixture.fetch(:vps)
    vps.update!(user_namespace_map: map)

    [fixture, vps, map]
  end

  it 'emits a DisuseMap transaction with pool, map, UID/GID, node, and VPS parameters' do
    fixture, vps, map = create_vps_with_namespace_map

    chain, = described_class.fire(vps, userns_map: map)
    transactions = transactions_for(chain)
    tx = transactions.fetch(0)
    payload = tx_payload(chain, Transactions::UserNamespace::DisuseMap)

    expect(transactions.size).to eq(1)
    expect(Transaction.for_type(tx.handle)).to eq(Transactions::UserNamespace::DisuseMap)
    expect(tx.node_id).to eq(vps.node_id)
    expect(tx.vps_id).to eq(vps.id)
    expect(payload).to include(
      'pool_fs' => fixture.fetch(:pool).filesystem,
      'name' => map.id.to_s,
      'uidmap' => map.build_map(:uid),
      'gidmap' => map.build_map(:gid)
    )
  end

  it 'falls back to the VPS namespace map when no explicit map is provided' do
    _fixture, vps, map = create_vps_with_namespace_map

    chain, = described_class.fire(vps)

    expect(tx_payload(chain, Transactions::UserNamespace::DisuseMap)).to include(
      'name' => map.id.to_s
    )
  end
end
