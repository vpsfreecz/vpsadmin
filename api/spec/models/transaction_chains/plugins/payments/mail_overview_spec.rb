# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'payments plugin mail overview chain', requires_plugins: :payments do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
  end

  it 'enqueues one overview mail with period buckets and accepted payments' do
    now = Time.local(2026, 4, 1, 12, 0, 0)
    allow(Time).to receive(:now).and_return(now)

    queued = build_incoming_payment!(transaction_id: 'overview-q', state: :queued)
    unmatched = build_incoming_payment!(transaction_id: 'overview-u', state: :unmatched)
    processed = build_incoming_payment!(transaction_id: 'overview-p', state: :processed)
    ignored = build_incoming_payment!(transaction_id: 'overview-i', state: :ignored)
    old = build_incoming_payment!(transaction_id: 'overview-old', state: :queued)
    old.update_column(:created_at, now - 3.days)

    accepted = UserPayment.new(
      incoming_payment: processed,
      user: SpecSeed.user,
      accounted_by: SpecSeed.admin,
      amount: 100,
      from_date: now - 1.month,
      to_date: now
    ).tap(&:save!)

    captured = nil
    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      expect(name).to eq(:payments_overview)
      expect(opts[:language]).to eq(SpecSeed.language)
      captured = opts.fetch(:vars)
      build_mail_log_double
    end

    chain, = chain_class.fire2(args: [86_400, SpecSeed.language])

    expect(tx_classes(chain)).to eq([Transactions::Mail::Send])
    expect(MailTemplate).to have_received(:send_mail!).once

    expect(captured[:base_url]).to eq(SysConfig.get(:webui, :base_url))
    expect(captured[:start]).to eq(now - 86_400)
    expect(captured[:end]).to eq(now)
    expect(captured[:incoming]).to include(queued, unmatched, processed, ignored)
    expect(captured[:incoming]).not_to include(old)
    expect(captured[:queued]).to include(queued)
    expect(captured[:unmatched]).to include(unmatched)
    expect(captured[:processed]).to include(processed)
    expect(captured[:ignored]).to include(ignored)
    expect(captured[:accepted]).to include(accepted)
  end
end
