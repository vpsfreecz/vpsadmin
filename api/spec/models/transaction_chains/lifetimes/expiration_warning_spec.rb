# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Lifetimes::ExpirationWarning do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:sent_mails) { [] }

  before do
    ensure_expiration_template!(object: 'user', state: 'active')
    ensure_expiration_template!(object: 'vps', state: 'active')
    ensure_mailer_available!
    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      sent_mails << [name, opts]
      build_mail_log_double
    end
  end

  it 'resolves a User as its own owner' do
    user = SpecSeed.create_or_update_user!(
      login: "expires-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'expires@test.invalid'
    )
    user.update!(expiration_date: 2.days.from_now)

    described_class.fire2(args: [User, [user]])

    expect(sent_mails.size).to eq(1)
    name, opts = sent_mails.first
    expect(name).to eq(:expiration_warning)
    expect(opts).to include(
      params: { object: 'user', state: 'active' },
      user:
    )
    expect(opts.fetch(:vars)).to include(object: user)
    expect(opts.fetch(:vars).fetch('user')).to eq(user)
  end

  it 'resolves the owner of user-owned objects such as VPSes' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    vps.update!(expiration_date: 2.days.from_now)

    described_class.fire2(args: [Vps, [vps]])

    expect(sent_mails.first.last).to include(
      params: { object: 'vps', state: 'active' },
      user: vps.user
    )
    expect(sent_mails.first.last.fetch(:vars)).to include(object: vps)
    expect(sent_mails.first.last.fetch(:vars).fetch('vps')).to eq(vps)
  end

  it 'skips users with mailer disabled' do
    user = SpecSeed.create_or_update_user!(
      login: "no-mail-#{SecureRandom.hex(4)}",
      level: 1,
      email: 'no-mail@test.invalid'
    )
    user.update!(expiration_date: 2.days.from_now, mailer_enabled: false)

    chain, = described_class.fire2(args: [User, [user]])

    expect(chain).to be_nil
    expect(MailTemplate).not_to have_received(:send_mail!)
  end

  it 'computes expiration day helper values' do
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    vps.update!(expiration_date: 1.day.from_now)

    described_class.fire2(args: [Vps, [vps]])

    vars = sent_mails.first.last.fetch(:vars)
    expect(vars.fetch(:expires_in_days)).to be_within(0.05).of(1.0)
    expect(vars.fetch(:expired_days_ago)).to be_within(0.05).of(-1.0)
    expect(vars.fetch(:expires_in_a_day)).to be(true)
  end

  it 'raises when no owner can be inferred' do
    unsupported = Struct.new(:expiration_date, :object_state).new(1.day.from_now, 'active')

    expect do
      described_class.fire2(args: [Object, [unsupported]])
    end.to raise_error(RuntimeError, /Unable to find an owner/)
  end
end
