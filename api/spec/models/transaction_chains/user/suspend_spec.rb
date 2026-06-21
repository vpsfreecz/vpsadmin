# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::Suspend do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before { ensure_user_notification_templates! }

  it 'sends suspend mail, stops VPSes, and disables user DNS state for target transitions' do
    fixture = create_user_lifecycle_fixture!

    chain, = described_class.fire(fixture.fetch(:user), true, nil, ObjectState.new)
    classes = tx_classes(chain)

    expect(classes).to include(
      Transactions::EventDelivery::Release,
      Transactions::Vps::Stop,
      Transactions::DnsServerZone::Update,
      Transactions::DnsServerZone::DeleteRecords
    )
    release_idx = classes.index(Transactions::EventDelivery::Release)
    expect(classes.rindex(Transactions::Vps::Stop)).to be < release_idx
    expect(classes.rindex(Transactions::DnsServerZone::Update)).to be < release_idx
    expect(classes.rindex(Transactions::DnsServerZone::DeleteRecords)).to be < release_idx
    expect(MailLog.joins(:notification_template).exists?(notification_templates: { name: 'user_suspend' })).to be(true)
    event = expect_routed_event!('user.suspended', user: fixture.fetch(:user))
    expect(event.source_class).to eq('ObjectState')
    expect(event.parameters).to include('state' => 'suspended')
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'DnsRecord' &&
        row.row_pks == { 'id' => fixture.fetch(:user_record).id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['enabled'] == 1
    end).to be(true)
  end

  it 'does not send mail or disable DNS for intermediate transitions' do
    fixture = create_user_lifecycle_fixture!

    chain, = described_class.fire(fixture.fetch(:user), false, nil, ObjectState.new)

    expect(tx_classes(chain)).to include(Transactions::Vps::Stop)
    expect(tx_classes(chain)).not_to include(
      Transactions::EventDelivery::Release,
      Transactions::DnsServerZone::Update,
      Transactions::DnsServerZone::DeleteRecords
    )
  end
end
