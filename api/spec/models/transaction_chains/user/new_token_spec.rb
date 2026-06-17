# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::NewToken do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'concerns the token owner and sends a notification mail' do
    user = create_lifecycle_user!
    session = create_detached_token_session!(user: user)

    chain, = described_class.fire(session)

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['User', user.id])
    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(MailLog.joins(:mail_template).exists?(mail_templates: { name: 'user_new_token' })).to be(true)

    event = expect_routed_event!('user.new_token', user:)
    expect(event.source).to eq(session)
    expect(event.parameters).to include(
      'auth_type' => 'token',
      'scope' => '*',
      'label' => 'spec-token'
    )
  end
end
