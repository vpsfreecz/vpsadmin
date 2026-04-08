# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::DeployUserData do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'queues a single deploy transaction with user-data and OS-template payloads' do
    template = create_os_template!(
      distribution: 'debian',
      version: '12',
      vendor: 'bookworm',
      variant: 'cloud'
    )
    fixture = build_standalone_vps_fixture(
      user: user,
      hostname: 'deploy-user-data',
      dns_resolver: nil
    )
    vps = fixture.fetch(:vps)
    vps.update!(os_template: template)
    user_data = create_vps_user_data!(
      user: user,
      format: 'script',
      content: "#!/bin/sh\necho phase2\n"
    )

    chain, = described_class.fire(vps, user_data)

    expect(tx_classes(chain)).to eq([Transactions::Vps::DeployUserData])
    expect(tx_payload(chain, Transactions::Vps::DeployUserData)).to include(
      'format' => 'script',
      'content' => "#!/bin/sh\necho phase2\n",
      'os_template' => include(
        'distribution' => 'debian',
        'version' => '12',
        'vendor' => 'bookworm',
        'variant' => 'cloud'
      )
    )
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Vps', vps.id])
    expect(confirmations_for(chain)).to eq([])
  end
end
