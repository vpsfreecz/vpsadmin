# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::DeployPublicKey do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'queues a single deploy transaction, locks only the VPS, and logs the key metadata' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'deploy-key')
    vps = fixture.fetch(:vps)
    key = create_user_public_key!(
      user: user,
      key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIdeploy deploy@test',
      auto_add: false,
      label: 'Deploy Key'
    )

    chain, = described_class.fire(vps, key)
    history = ObjectHistory.where(tracked_object: vps, event_type: 'deploy_public_key').sole

    expect(tx_classes(chain)).to eq([Transactions::Vps::DeployPublicKey])
    expect(tx_payload(chain, Transactions::Vps::DeployPublicKey)).to include('pubkey' => key.key)
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Vps', vps.id])
    expect(confirmations_for(chain).map(&:class_name)).to eq(['ObjectHistory'])
    expect(history.event_data).to include(
      'id' => key.id,
      'label' => key.label,
      'key' => key.key
    )
  end
end
