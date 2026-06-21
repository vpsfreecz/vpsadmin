# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::Revive do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before { ensure_user_notification_templates! }

  it 'sends revive mail, re-enables exports, and moves soft-deleted VPSes to active' do
    fixture = create_user_lifecycle_fixture!
    fixture.fetch(:vps).update!(object_state: :soft_delete)
    fixture.fetch(:export).update!(enabled: false, original_enabled: true)
    fixture.fetch(:owned_zone).update!(enabled: false, original_enabled: true)

    chain, = described_class.fire(fixture.fetch(:user), true, nil, ObjectState.new)
    classes = tx_classes(chain)

    expect(classes).to include(
      Transactions::EventDelivery::Release,
      Transactions::Export::Enable,
      Transactions::Vps::Start
    )
    release_idx = classes.index(Transactions::EventDelivery::Release)
    expect(classes.rindex(Transactions::Export::Enable)).to be < release_idx
    expect(classes.rindex(Transactions::Vps::Start)).to be < release_idx
    expect(MailLog.joins(:notification_template).exists?(notification_templates: { name: 'user_revive' })).to be(true)
    event = expect_routed_event!('user.revived', user: fixture.fetch(:user))
    expect(event.source_class).to eq('ObjectState')
    expect(event.parameters).to include('state' => 'active')
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Vps' &&
        row.row_pks == { 'id' => fixture.fetch(:vps).id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['object_state'] == Vps.object_states[:active]
    end).to be(true)
    expect(confirmations_for(chain).any? do |row|
      row.class_name == 'Export' &&
        row.row_pks == { 'id' => fixture.fetch(:export).id } &&
        row.attr_changes == { 'enabled' => 1 }
    end).to be(true)
  end
end
