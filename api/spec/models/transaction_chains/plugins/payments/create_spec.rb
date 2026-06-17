# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'payments plugin create chain', requires_plugins: :payments do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Payments::TransactionChains::Create }
  let(:user) { SpecSeed.user }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    seed_payments_sysconfig!
    user.update!(object_state: :active, mailer_enabled: true)
    user.user_account.update!(monthly_payment: 100, paid_until: nil)
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  it 'extends paid_until from an existing date and processes the incoming payment' do
    paid_until = Time.local(2026, 1, 15, 12, 30, 0)
    user.user_account.update!(paid_until: paid_until)
    incoming = build_incoming_payment!(amount: 200)
    payment = build_user_payment(user: user, incoming_payment: incoming, amount: 200)

    allow(user).to receive(:set_expiration).and_call_original

    chain, ret = chain_class.fire2(args: [payment])

    expect(ret).to eq(payment)
    expect(payment).to be_persisted
    expect(payment.from_date.to_i).to eq(paid_until.to_i)
    expect(payment.to_date.to_i).to eq(Time.local(2026, 3, 15, 12, 30, 0).to_i)
    expect(user.user_account.reload.paid_until.to_i).to eq(payment.to_date.to_i)
    expect(incoming.reload.state).to eq('processed')
    expect(user).to have_received(:set_expiration).with(
      payment.to_date,
      reason: "Payment ##{payment.id} accepted."
    )
    expect(MailTemplate).to have_received(:send_mail!).with(
      :payment_accepted,
      hash_including(user: user, vars: hash_including(payment: payment))
    )
    event = Event.where(event_type: 'payment.accepted').sole
    delivery = event.event_deliveries.sole
    expect(event.user).to eq(user)
    expect(event.source).to eq(payment)
    expect(event.parameters).to include(
      'payment_id' => payment.id,
      'received_amount' => payment.received_amount.to_s('F'),
      'received_currency' => payment.received_currency,
      'incoming_payment_id' => incoming.id,
      'incoming_transaction_id' => incoming.transaction_id,
      'accounted_by_id' => SpecSeed.admin.id,
      'accounted_by_login' => SpecSeed.admin.login
    )
    expect(delivery).to be_queued_state
    expect(delivery.action).to eq('email')
    expect(delivery.template_name).to eq('payment_accepted')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['UserPayment', payment.id]
    )
  end

  it 'extends paid_until from now when the account was not paid' do
    now = Time.local(2026, 4, 1, 10, 0, 0)
    allow(Time).to receive(:now).and_return(now)
    incoming = build_incoming_payment!(amount: 300)
    payment = build_user_payment(user: user, incoming_payment: incoming, amount: 300)

    chain_class.fire2(args: [payment])

    expect(payment.from_date.to_i).to eq(now.to_i)
    expect(payment.to_date.to_i).to eq(Time.local(2026, 7, 1, 10, 0, 0).to_i)
    expect(user.user_account.reload.paid_until.to_i).to eq(payment.to_date.to_i)
    expect(incoming.reload.state).to eq('processed')
  end

  it 'emits readable event parameters for manual payments' do
    payment = build_user_payment(user: user, amount: 200)

    chain_class.fire2(args: [payment])

    event = Event.where(event_type: 'payment.accepted').sole
    expect(event.parameters).to include(
      'amount' => 200,
      'received_amount' => 200,
      'received_currency' => 'CZK'
    )
    expect(event.parameters).not_to have_key('incoming_payment_id')
    expect(event.parameters).not_to have_key('incoming_transaction_id')
  end

  it 'uses the object-state chain and confirmation operations for suspended users' do
    user.update!(object_state: :suspended)
    incoming = build_incoming_payment!(amount: 100)
    payment = build_user_payment(user: user, incoming_payment: incoming, amount: 100)

    allow(user).to receive(:set_object_state).and_call_original

    chain, = chain_class.fire2(args: [payment])

    expect(user).to have_received(:set_object_state).with(
      :active,
      expiration: payment.to_date,
      reason: "Payment ##{payment.id} accepted.",
      chain: kind_of(TransactionChain)
    )
    expect(user.user_account.reload.paid_until.to_i).to eq(payment.to_date.to_i)
    expect(incoming.reload.state).to eq('queued')
    expect(tx_classes(chain)).to include(Transactions::Utils::NoOp)

    confirmations = confirmations_for(chain)
    expect(confirmations).to include(
      have_attributes(class_name: 'UserPayment', confirm_type: 'just_create_type'),
      have_attributes(class_name: 'UserAccount', confirm_type: 'edit_before_type'),
      have_attributes(class_name: 'IncomingPayment', confirm_type: 'edit_after_type')
    )
    expect(confirmations.find { |c| c.class_name == 'IncomingPayment' }.attr_changes)
      .to eq('state' => IncomingPayment.states[:processed])
  end

  it 'raises for disabled accounts' do
    user.update!(object_state: :soft_delete)
    payment = build_user_payment(
      user: user,
      incoming_payment: build_incoming_payment!(amount: 100),
      amount: 100
    )

    expect do
      chain_class.fire2(args: [payment])
    end.to raise_error(UserAccount::AccountDisabled, /cannot add payment/)
  end
end
