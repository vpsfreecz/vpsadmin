# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Mail::DailyReport do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  it 'queues a mail send transaction' do
    chain, = described_class.fire2(args: [SpecSeed.language])

    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailTemplate).to have_received(:send_mail!).with(
      :daily_report,
      hash_including(language: SpecSeed.language)
    )
  end

  it 'builds the major template sections' do
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    vps = fixture.fetch(:vps)
    create_oom_report_fixture!(vps:, count: 4, killed_name: 'daily-worker')
    OomPrevention.create!(vps:, action: :restart)

    vars = described_class.new.send(:vars, Time.now.utc)

    expect(vars.keys).to include(
      :users,
      :vps,
      :datasets,
      :snapshots,
      :downloads,
      :chains,
      :transactions,
      :backups,
      :dataset_expansions,
      :oom_reports,
      :oom_preventions
    )
    expect(vars.dig(:users, :active, :all)).to include(SpecSeed.user)
    expect(vars.dig(:vps, :active, :all)).to include(vps)
    expect(vars.dig(:oom_reports, :by_killed_name)).to include(['daily-worker', 4])
    expect(vars.dig(:oom_reports, :preventions)).to include(OomPrevention.last)
  end

  it 'merges hook output into the final vars payload' do
    captured_vars = nil
    chain_instance = described_class.new
    allow(described_class).to receive(:new).and_return(chain_instance)
    allow(MailTemplate).to receive(:send_mail!) do |_name, opts|
      captured_vars = opts.fetch(:vars)
      build_mail_log_double
    end
    allow(chain_instance).to receive(:call_hooks_for) do |hook, _context, args:, initial:|
      expect(hook).to eq(:send)
      expect(args.size).to eq(2)
      initial.merge(hook_output: { ok: true })
    end

    described_class.fire2(args: [SpecSeed.language])

    expect(captured_vars).to include(hook_output: { ok: true })
    expect(captured_vars).to include(:users, :transactions)
  end
end
