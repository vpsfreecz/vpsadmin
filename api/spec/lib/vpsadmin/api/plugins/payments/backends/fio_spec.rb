# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'payments Fio backend', requires_plugins: :payments do # rubocop:disable RSpec/DescribeClass
  let(:backend_class) { VpsAdmin::API::Plugins::Payments::Backends::Fio }

  def fio_transaction(attrs)
    klass = Struct.new(
      :transaction_id,
      :date,
      :amount,
      :currency,
      :account_name,
      :user_identification,
      :message_for_recipient,
      :vs,
      :ks,
      :ss,
      :transaction_type,
      :comment,
      :detail_info
    )
    klass.new(**attrs)
  end

  def stub_fio_transactions(*transactions)
    response = Struct.new(:transactions).new(transactions)
    list = instance_double(FioAPI::List, response: response)

    allow(list).to receive(:from_last_fetch)
    allow(FioAPI::List).to receive(:new).and_return(list)
    allow(SysConfig).to receive(:get).and_call_original
    allow(SysConfig).to receive(:get).with(:plugin_payments, :fio_api_tokens).and_return(['token-a'])
  end

  it 'persists positive incoming payments and splits source details' do
    stub_fio_transactions(
      fio_transaction(
        transaction_id: 'fio-1',
        date: Date.today,
        amount: 123.45,
        currency: 'CZK',
        account_name: 'Sender',
        user_identification: 'User Ident',
        message_for_recipient: 'hello',
        vs: '100',
        ks: '200',
        ss: '300',
        transaction_type: nil,
        comment: 'comment',
        detail_info: '5.50 EUR'
      )
    )

    backend_class.new.fetch

    payment = IncomingPayment.find_by!(transaction_id: 'fio-1')
    expect(payment.amount).to eq(123.45)
    expect(payment.currency).to eq('CZK')
    expect(payment.account_name).to eq('Sender')
    expect(payment.user_ident).to eq('User Ident')
    expect(payment.user_message).to eq('hello')
    expect(payment.vs).to eq('100')
    expect(payment.transaction_type).to eq('unset')
    expect(payment.src_amount).to eq(5.50)
    expect(payment.src_currency).to eq('EUR')
  end

  it 'ignores outgoing payments' do
    stub_fio_transactions(
      fio_transaction(
        transaction_id: 'fio-out',
        date: Date.today,
        amount: -10,
        currency: 'CZK'
      )
    )

    backend_class.new.fetch

    expect(IncomingPayment.exists?(transaction_id: 'fio-out')).to be(false)
  end

  it 'warns and skips duplicate transaction IDs' do
    build_incoming_payment!(transaction_id: 'fio-dup')
    stub_fio_transactions(
      fio_transaction(
        transaction_id: 'fio-dup',
        date: Date.today,
        amount: 10,
        currency: 'CZK',
        transaction_type: 'credit'
      )
    )

    _out, err = capture_streams { backend_class.new.fetch }

    expect(err).to include("Duplicit transaction ID 'fio-dup'")
    expect(IncomingPayment.where(transaction_id: 'fio-dup').count).to eq(1)
  end
end
