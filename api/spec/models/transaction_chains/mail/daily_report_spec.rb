# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Mail::DailyReport do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_alert_notification_templates!
    ensure_mailer_available!
    create_admin_system_report_route!(
      event_type: 'system.daily_report',
      template_name: 'daily_report'
    )
    allow(NotificationTemplate).to receive(:send_email!).and_return(build_mail_log_double)
  end

  def create_admin_system_report_route!(event_type:, template_name:)
    receiver = NotificationReceiver.create!(user: SpecSeed.admin, label: "Spec #{template_name} receiver")
    receiver.notification_receiver_actions.create!(
      action: :email,
      target_kind: :default_recipient
    )
    route = EventRoute.create!(
      user: SpecSeed.admin,
      notification_receiver: receiver,
      label: "Spec #{template_name} system route",
      event_type:,
      template_name:,
      subject_scope: :visible,
      position: 1
    )
  end

  it 'queues an event delivery release transaction' do
    chain, = described_class.fire2(args: [SpecSeed.language])

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Notify)
    expect(NotificationTemplate).to have_received(:send_email!).with(
      :daily_report,
      hash_including(language: SpecSeed.language)
    )
    event = Event.where(event_type: 'system.daily_report').sole
    delivery = event.event_deliveries.sole
    expect(delivery.event_route.event_route_matchers).to be_empty
    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'language_id' => SpecSeed.language.id,
      'language_code' => SpecSeed.language.code,
      'period_seconds' => described_class::PERIOD_SECONDS
    )
    expect(event.parameters.fetch('period_start')).to be_present
    expect(event.parameters.fetch('period_end')).to be_present
    expect(delivery).not_to be_direct_email_delivery
    expect(delivery.event_routing_context.recipient_user).to eq(SpecSeed.admin)
    expect(delivery.event_routing_context.subject_relation).to eq('system')
    expect(delivery.template_name).to eq('daily_report')
    expect(delivery.target_label).to eq('Default recipient')
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
    allow(NotificationTemplate).to receive(:send_email!) do |_name, opts|
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

  it 'raises when the event e-mail delivery cannot be queued' do
    allow(NotificationTemplate).to receive(:send_email!).and_raise(ArgumentError, 'invalid report')

    expect do
      described_class.fire2(args: [SpecSeed.language])
    end.to raise_error(
      RuntimeError,
      /failed to queue daily report e-mail delivery: ArgumentError: invalid report/
    )
  end

  context 'with payments plugin hooks', requires_plugins: :payments do
    it 'augments vars with incoming and accepted payments' do
      incoming = build_incoming_payment!(transaction_id: 'daily-incoming', state: :queued)
      accepted = UserPayment.new(
        incoming_payment: incoming,
        user: SpecSeed.user,
        accounted_by: SpecSeed.admin,
        amount: 100,
        from_date: 1.month.ago,
        to_date: Time.now
      ).tap(&:save!)
      captured_vars = nil

      allow(NotificationTemplate).to receive(:send_email!) do |_name, opts|
        captured_vars = opts.fetch(:vars)
        build_mail_log_double
      end

      described_class.fire2(args: [SpecSeed.language])

      expect(captured_vars.dig(:payments, :incoming)).to include(incoming)
      expect(captured_vars.dig(:payments, :queued)).to include(incoming)
      expect(captured_vars.dig(:payments, :accepted)).to include(accepted)
    end
  end

  context 'with webui plugin hook', requires_plugins: :webui do
    it 'adds the configured webui base URL' do
      SysConfig.find_by!(category: 'webui', name: 'base_url')
               .update!(value: 'https://webui.example.test')
      captured_vars = nil

      allow(NotificationTemplate).to receive(:send_email!) do |_name, opts|
        captured_vars = opts.fetch(:vars)
        build_mail_log_double
      end

      described_class.fire2(args: [SpecSeed.language])

      expect(captured_vars[:base_url]).to eq('https://webui.example.test')
    end
  end
end
