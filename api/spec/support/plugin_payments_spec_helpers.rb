# frozen_string_literal: true

require 'securerandom'

module PluginPaymentsSpecHelpers
  def build_incoming_payment!(attrs = {})
    IncomingPayment.create!({
      transaction_id: attrs.fetch(:transaction_id, "spec-#{SecureRandom.hex(4)}"),
      date: attrs.fetch(:date, Date.today),
      amount: attrs.fetch(:amount, 200),
      currency: attrs.fetch(:currency, 'CZK'),
      account_name: attrs.fetch(:account_name, 'Spec Sender'),
      state: attrs.fetch(:state, :queued),
      transaction_type: attrs.fetch(:transaction_type, 'credit')
    }.merge(attrs.except(:transaction_id, :date, :amount, :currency, :account_name, :state, :transaction_type)))
  end

  def build_user_payment(user:, incoming_payment: nil, amount: 200)
    UserPayment.new(
      user: user,
      incoming_payment: incoming_payment,
      amount: amount,
      from_date: Time.now,
      to_date: Time.now,
      accounted_by: SpecSeed.admin
    )
  end
end

RSpec.configure do |config|
  config.include PluginPaymentsSpecHelpers
end
