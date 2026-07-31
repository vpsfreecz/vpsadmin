# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Lifetimes::ExpirationWarning do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_expiration_template!(object: 'user', state: 'active')
    ensure_expiration_template!(object: 'vps', state: 'active')
    ensure_mailer_available!
  end

  def stub_mail_delivery!
    allow(::Mail).to receive(:new).and_wrap_original do |original, *args|
      message = original.call(*args)
      response = instance_double(
        Net::SMTP::Response,
        status: '250',
        string: '250 2.0.0 queued as expiration-warning-spec'
      )
      allow(message).to receive(:deliver!).and_return(response)
      message
    end
  end

  it 'resolves a User as its own owner' do
    user = SpecSeed.create_or_update_user!(
      login: "expires-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'expires@test.invalid'
    )
    user.update!(expiration_date: 2.days.from_now)

    chain, = described_class.fire2(args: [User, [user]])

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    event = expect_routed_event!('lifetime.expiration_warning', user:)
    expect(event.source).to eq(user)
    expect(event.parameters).to include(
      'object' => 'user',
      'object_id' => user.id,
      'object_label' => user.login,
      'state' => 'active'
    )
    expect(event.event_deliveries.sole.mail_log.notification_template.name).to eq('expiration_user_active')
  end

  it 'resolves the owner of user-owned objects such as VPSes' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    vps.update!(expiration_date: 2.days.from_now)

    chain, = described_class.fire2(args: [Vps, [vps]])

    expect(tx_classes(chain)).to include(Transactions::EventDelivery::Release)
    event = expect_routed_event!('lifetime.expiration_warning', user: vps.user)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(vps)
    expect(event.parameters).to include(
      'object' => 'vps',
      'object_id' => vps.id,
      'object_label' => vps.hostname,
      'state' => 'active'
    )
    expect(event.event_deliveries.sole.mail_log.notification_template.name).to eq('expiration_vps_active')
  end

  it 'persists suppressed notifications for users with muted default notifications' do
    user = SpecSeed.create_or_update_user!(
      login: "no-mail-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'no-mail@test.invalid'
    )
    user.update!(expiration_date: 2.days.from_now)
    mute_default_notifications_for!(user)

    chain, = described_class.fire2(args: [User, [user]])
    event = expect_suppressed_event!('lifetime.expiration_warning', user:)

    expect(chain).to be_nil
    expect(event.source).to eq(user)
    expect(event.event_deliveries.sole.error_summary).to include('does not notify')
  end

  it 'computes expiration day helper values' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    vps.update!(expiration_date: 1.day.from_now)

    described_class.fire2(args: [Vps, [vps]])

    params = Event.where(event_type: 'lifetime.expiration_warning', user: vps.user).sole.parameters

    expect(params.fetch('expires_in_days')).to be_within(0.05).of(1.0)
    expect(params.fetch('expired_days_ago')).to be_within(0.05).of(-1.0)
    expect(params.fetch('expires_in_a_day')).to be(true)
  end

  it 'renders delayed e-mail deliveries from persisted template parameters' do
    user = SpecSeed.create_or_update_user!(
      login: "delayed-expiration-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'delayed-expiration@test.invalid'
    )
    expiration_date = 2.days.from_now
    user.update!(expiration_date:)
    event = VpsAdmin::API::Events.emit!(
      'lifetime.expiration_warning',
      user:,
      source: user,
      subject: 'Delayed expiration warning',
      parameters: {
        object: 'user',
        object_id: user.id,
        object_label: user.login,
        state: user.object_state,
        expiration_date: expiration_date.iso8601,
        expires_in_days: 2.0,
        expired_days_ago: -2.0,
        expires_in_a_day: false
      }
    )
    delivery = event.event_deliveries.sole
    delivery.reload

    expect(delivery).to be_released_state
    expect(delivery.mail_log.notification_template.name).to eq('expiration_user_active')
    expect(delivery.mail_log.text_plain).to include('approximately 2 days')

    stub_mail_delivery!
    VpsAdmin::API::Tasks::EventDelivery.new.deliver_emails

    delivery.reload
    expect(delivery).to be_sent_state
  end

  it 'raises when no owner can be inferred' do
    unsupported = Struct.new(:expiration_date, :object_state).new(1.day.from_now, 'active')

    expect do
      described_class.fire2(args: [Object, [unsupported]])
    end.to raise_error(RuntimeError, /Unable to find an owner/)
  end
end
