# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'payments plugin metrics', requires_plugins: :payments do # rubocop:disable RSpec/DescribeClass
  it 'exports monthly payment and paid-until for the current token user' do
    user = SpecSeed.user
    paid_until = Time.local(2026, 5, 1, 12, 0, 0)
    user.user_account.update!(monthly_payment: 321, paid_until: paid_until)
    token = MetricsAccessToken.create_for!(user, 'spec_payments_')
    registry = Prometheus::Client::Registry.new
    metrics = VpsAdmin::API::Plugins::Payments::Metrics.new(registry, token)

    metrics.setup
    metrics.compute

    output = Prometheus::Client::Formats::Text.marshal(registry)
    expect(output).to include('spec_payments_user_monthly_payment 321')
    expect(output).to include("spec_payments_user_paid_until #{paid_until.to_i}")
  end
end
