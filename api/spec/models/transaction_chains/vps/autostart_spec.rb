# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Autostart do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'enables autostart with the requested priority and logs the change' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'autostart-enable')
    vps = fixture.fetch(:vps)

    chain, = described_class.fire(vps, enable: true, priority: 250)
    history = ObjectHistory.where(tracked_object: vps, event_type: 'autostart').sole
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Vps' && row.row_pks == { 'id' => vps.id }
    end

    expect(tx_classes(chain)).to eq([Transactions::Vps::Autostart])
    expect(tx_payload(chain, Transactions::Vps::Autostart)).to include(
      'new' => include('enable' => true, 'priority' => 250)
    )
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', vps.id])
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(['Vps', vps.id])
    expect(confirmation&.attr_changes).to include(
      'autostart_enable' => 1,
      'autostart_priority' => 250
    )
    expect(history.event_data).to include('enable' => true, 'priority' => 250)
  end

  it 'disables autostart while preserving the current priority in the DB edit and log row' do
    fixture = build_standalone_vps_fixture(user: user, hostname: 'autostart-disable')
    vps = fixture.fetch(:vps)
    vps.update!(autostart_enable: true, autostart_priority: 444)

    chain, = described_class.fire(vps, enable: false)
    history = ObjectHistory.where(tracked_object: vps, event_type: 'autostart').sole
    confirmation = confirmations_for(chain).find do |row|
      row.class_name == 'Vps' && row.row_pks == { 'id' => vps.id }
    end

    expect(tx_classes(chain)).to eq([Transactions::Vps::Autostart])
    expect(tx_payload(chain, Transactions::Vps::Autostart)).to include(
      'new' => include('enable' => false, 'priority' => 444)
    )
    expect(confirmation&.attr_changes).to include(
      'autostart_enable' => 0,
      'autostart_priority' => 444
    )
    expect(history.event_data).to include('enable' => false, 'priority' => 444)
  end
end
