# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::OomReports do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_notification_templates!
    ensure_mailer_available!
    allow(NotificationTemplate).to receive(:send_email!).and_return(build_mail_log_double)
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
    expect(NotificationTemplate).not_to have_received(:send_email!)
    expect(unreported.reload.reported_at).to be_nil
  end

  it 'sends mail and marks selected reports when cooldown allows it' do
    vps = create_vps!
    reports = 2.times.map do |i|
      create_oom_report_fixture!(vps:, count: i + 1, created_at: (5 - i).minutes.ago)
    end

    chain, = described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(NotificationTemplate).to have_received(:send_email!).with(
      :vps_oom_report,
      hash_including(
        user: vps.user,
        vars: hash_including(vps:, all_oom_count: 3, selected_oom_count: 3)
      )
    )
    expect(reports.map { |report| report.reload.reported_at }).to all(be_present)
  end

  it 'marks selected reports when notification routing is muted' do
    vps = create_vps!
    mute_default_notifications_for!(vps.user)
    reports = 2.times.map do |i|
      create_oom_report_fixture!(vps:, count: i + 1, created_at: (5 - i).minutes.ago)
    end

    chain, = described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })
    event = expect_suppressed_event!('vps.oom_report', user: vps.user)

    expect(chain).to be_nil
    expect(NotificationTemplate).not_to have_received(:send_email!)
    expect(event.event_deliveries.sole.error_summary).to include('does not notify')
    expect(reports.map { |report| report.reload.reported_at }).to all(be_present)
  end

  it 'renders the installed notification template with the chain variables' do
    allow(NotificationTemplate).to receive(:send_email!).and_call_original

    vps = create_vps!
    2.times do |i|
      create_oom_report_fixture!(vps:, count: i + 1, created_at: (5 - i).minutes.ago)
    end

    chain, = described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })
    mail = MailLog.where(notification_template: NotificationTemplate.find_by!(name: 'vps_oom_report')).last

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    expect(mail.text_plain).to include('Selected events: 3 of 3')
    expect(mail.text_plain).to include("VPS ##{vps.id}")
  end

  it 'keeps reports retryable when e-mail cannot be queued' do
    allow(NotificationTemplate).to receive(:send_email!).and_raise(
      ArgumentError,
      'render failed'
    )
    vps = create_vps!
    report = create_oom_report_fixture!(vps:, created_at: 1.minute.ago)

    expect do
      described_class.fire2(args: [[vps]], kwargs: { cooldown: 1.hour })
    end.to raise_error(RuntimeError, /failed to prepare OOM report e-mail delivery/)

    expect(report.reload.reported_at).to be_nil
    expect(Event.where(event_type: 'vps.oom_report')).to be_empty
  end

  it 'considers only reports after the most recently reported report' do
    captured_ids = nil
    allow(NotificationTemplate).to receive(:send_email!) do |_name, opts|
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
    allow(NotificationTemplate).to receive(:send_email!) do |_name, opts|
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

  it 'handles more reports than the event parameter array limit' do
    vps = create_vps!
    reports = 101.times.map do |i|
      create_oom_report_fixture!(vps:, count: 1, created_at: (120 - i).minutes.ago)
    end

    expect do
      described_class.fire2(args: [[vps]], kwargs: { cooldown: 1 })
    end.to change(Event.where(event_type: 'vps.oom_report'), :count).by(1)

    event = Event.where(event_type: 'vps.oom_report').order(:id).last
    delivery = event.event_deliveries.sole

    expect(delivery).to be_prepared_state
    expect(event.parameters['stage']).to eq('notification')
    expect(event.parameters['selected_report_ids'].count).to eq(30)
    expect(event.parameters).not_to have_key('report_ids')
    expect(event.parameters['report_count']).to eq(101)
    expect(event.parameters['oom_count']).to eq(101)
    expect(reports.map { |report| report.reload.reported_at }).to all(be_present)
  end
end
