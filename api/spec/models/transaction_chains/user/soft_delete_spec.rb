# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::SoftDelete do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before { ensure_user_mail_templates! }

  it 'sends mail, cascades runtime disables, records VPS soft-delete, and closes auth state' do
    fixture = create_user_lifecycle_fixture!(token_session: false)
    user = fixture.fetch(:user)
    auth = create_auth_cleanup_fixture!(user: user)

    chain, = described_class.fire(user, true, nil, ObjectState.new)
    classes = tx_classes(chain)
    confirmations = confirmations_for(chain)

    expect(classes).to include(
      Transactions::Mail::Send,
      Transactions::Vps::Stop,
      Transactions::Export::Disable,
      Transactions::DnsServerZone::Update,
      Transactions::DnsServerZone::DeleteRecords
    )
    expect(MailLog.joins(:mail_template).exists?(mail_templates: { name: 'user_soft_delete' })).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'Vps' &&
        row.row_pks == { 'id' => fixture.fetch(:vps).id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['object_state'] == Vps.object_states[:soft_delete]
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'Export' &&
        row.row_pks == { 'id' => fixture.fetch(:export).id } &&
        row.attr_changes == { 'enabled' => 0 }
    end).to be(true)
    expect(confirmations.any? do |row|
      row.class_name == 'DnsRecord' &&
        row.row_pks == { 'id' => fixture.fetch(:user_record).id } &&
        row.attr_changes.is_a?(Hash) &&
        row.attr_changes['enabled'] == 1
    end).to be(true)

    expect(auth.fetch(:token_session).reload.token_id).to be_nil
    expect(auth.fetch(:token_session).closed_at).not_to be_nil
    expect(SingleSignOn.exists?(auth.fetch(:single_sign_on).id)).to be(false)
    expect(Oauth2Authorization.exists?(auth.fetch(:oauth2_authorization).id)).to be(false)
    expect(MetricsAccessToken.exists?(auth.fetch(:metrics_access_token).id)).to be(false)
  end
end
