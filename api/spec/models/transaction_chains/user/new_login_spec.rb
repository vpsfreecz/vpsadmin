# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::NewLogin do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'concerns the logged-in user and sends a notification mail' do
    user = create_lifecycle_user!
    auth = create_auth_cleanup_fixture!(user: user)

    chain, = described_class.fire(auth.fetch(:token_session), auth.fetch(:oauth2_authorization))

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['User', user.id])
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailLog.joins(:mail_template).exists?(mail_templates: { name: 'user_new_login' })).to be(true)
  end
end
