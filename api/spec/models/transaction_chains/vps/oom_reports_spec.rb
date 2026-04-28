# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::OomReports do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_mail_templates!
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)
  end

  def create_vps!
    build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
  end

  it 'suppresses notification during the cooldown' do
    vps = create_vps!
    create_oom_report_fixture!(
      vps:,
      created_at: 10.minutes.ago,
      reported_at: 5.minutes.ago
    )
    unreported = create_oom_report_fixture!(vps:, created_at: 1.minute.ago)

    chain, = described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })

    expect(chain).to be_nil
    expect(MailTemplate).not_to have_received(:send_mail!)
    expect(unreported.reload.reported_at).to be_nil
  end

  it 'sends mail and marks selected reports when cooldown allows it' do
    vps = create_vps!
    reports = 2.times.map do |i|
      create_oom_report_fixture!(vps:, count: i + 1, created_at: (5 - i).minutes.ago)
    end

    chain, = described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })

    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailTemplate).to have_received(:send_mail!).with(
      :vps_oom_report,
      hash_including(
        user: vps.user,
        vars: hash_including(vps:, all_oom_count: 3, selected_oom_count: 3)
      )
    )
    expect(reports.map { |report| report.reload.reported_at }).to all(be_present)
  end

  it 'considers only reports after the most recently reported report' do
    captured_ids = nil
    allow(MailTemplate).to receive(:send_mail!) do |_name, opts|
      captured_ids = opts.fetch(:vars).fetch(:all_oom_reports).pluck(:id)
      build_mail_log_double
    end

    vps = create_vps!
    old_unreported = create_oom_report_fixture!(vps:, created_at: 10.minutes.ago)
    create_oom_report_fixture!(vps:, created_at: 9.minutes.ago, reported_at: 8.minutes.ago)
    new_unreported = create_oom_report_fixture!(vps:, created_at: 1.minute.ago)

    described_class.fire2(args: [[vps]], kwargs: { cooldown: 1 })

    expect(captured_ids).to eq([new_unreported.id])
    expect(old_unreported.reload.reported_at).to be_nil
    expect(new_unreported.reload.reported_at).to be_present
  end

  it 'limits selected reports to 30 while keeping all reports in the full set' do
    captured = nil
    allow(MailTemplate).to receive(:send_mail!) do |_name, opts|
      vars = opts.fetch(:vars)
      captured = {
        all_ids: vars.fetch(:all_oom_reports).pluck(:id),
        selected_ids: vars.fetch(:selected_oom_reports).pluck(:id)
      }
      build_mail_log_double
    end

    vps = create_vps!
    reports = 35.times.map do |i|
      create_oom_report_fixture!(vps:, count: 1, created_at: (35 - i).minutes.ago)
    end

    described_class.fire2(args: [[vps]], kwargs: { cooldown: 1 })

    expect(captured.fetch(:all_ids)).to eq(reports.map(&:id))
    expect(captured.fetch(:selected_ids)).to eq(reports.first(30).map(&:id))
    expect(reports.map { |report| report.reload.reported_at }).to all(be_present)
  end
end
