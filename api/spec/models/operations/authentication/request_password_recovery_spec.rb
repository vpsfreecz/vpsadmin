# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery do
  let(:request) { build_request(user_agent: 'Password recovery spec') }

  before do
    unlock_transaction_signer!
    ensure_available_node_status!(SpecSeed.node)
    VpsAdmin::API::MailTemplates.install_defaults!
    SysConfig.find_or_create_by!(category: 'core', name: 'api_url').update!(
      value: 'https://auth.example.test'
    )
    SysConfig.find_or_create_by!(category: 'core', name: 'support_mail').update!(
      value: 'support@example.test'
    )
    SysConfig.find_or_create_by!(category: 'core', name: 'password_recovery_enabled').update!(
      value: true
    )
  end

  def create_user(login:, email:, mfa: true, oauth2: true)
    create_lifecycle_user!(login:, email:).tap do |user|
      user.update!(
        enable_multi_factor_auth: mfa,
        enable_oauth2_auth: oauth2
      )
      create_totp_device!(user:) if mfa
    end
  end

  it 'sends one account-neutral mail with one entry per matching login' do
    email = 'Shared.Address@example.test'
    first = create_user(login: 'shared-a', email:)
    second = create_user(login: 'shared-b', email:, mfa: false)
    third = create_user(login: 'shared-c', email:, oauth2: false)

    recovery_request = described_class.run(
      'shared.address@EXAMPLE.test',
      locale: :en,
      oauth2_client: nil,
      request:
    )

    expect(recovery_request).to be_present
    expect(recovery_request.mail_log).to be_present
    expect(recovery_request.mail_log.user).to be_nil
    expect(recovery_request.mail_log.to).to eq(email)
    expect(recovery_request.mail_log.cc).to eq('')
    expect(recovery_request.mail_log.bcc).to eq('')
    expect(recovery_request.password_recoveries.order(:user_id).pluck(:user_id, :outcome)).to contain_exactly(
      [first.id, 'recoverable'],
      [second.id, 'no_mfa'],
      [third.id, 'unavailable']
    )

    body = recovery_request.mail_log.text_plain
    expect(body).to include('Login: shared-a', 'Login: shared-b', 'Login: shared-c')
    expect(body.scan('/oauth2/password-reset/continue#token=').length).to eq(1)
    expect(body).not_to include('can be used once', 'recovery code')

    html = recovery_request.mail_log.text_html
    expect(html).to include('Login: shared-a', 'Login: shared-b', 'Login: shared-c')
    expect(html).to include('class="action"', '>Set a new password</a>')
    expect(html.scan('/oauth2/password-reset/continue#token=').length).to eq(1)
    expect(html).not_to include('can be used once', 'recovery code')

    raw_token = body.match(/#token=([^\s]+)/)[1]
    recovery = recovery_request.password_recoveries.find_by!(user: first)
    expect(recovery.email_token_digest).to eq(PasswordRecovery.digest_token(raw_token))
    expect(recovery.email_token_digest).not_to eq(raw_token)
  end

  it 'prefers an exact case-sensitive login over email matching' do
    selected = create_user(login: 'shared-login', email: 'shared@example.test')
    create_user(login: 'other-shared', email: 'shared-login')

    recovery_request = described_class.run(
      'shared-login',
      locale: :en,
      oauth2_client: nil,
      request:
    )

    expect(recovery_request.password_recoveries.pluck(:user_id)).to eq([selected.id])
    expect(recovery_request.recipient_email).to eq('shared@example.test')
  end

  it 'does not create records for an unknown identifier' do
    expect do
      result = described_class.run(
        'nobody@example.test',
        locale: :en,
        oauth2_client: nil,
        request:
      )
      expect(result).to be_nil
    end.not_to change(PasswordRecoveryRequest, :count)
  end

  it 'throttles a destination for ten minutes' do
    user = create_user(login: 'throttled-user', email: 'throttled@example.test')

    first = described_class.run(
      user.email,
      locale: :en,
      oauth2_client: nil,
      request:
    )

    expect do
      second = described_class.run(
        user.email.upcase,
        locale: :en,
        oauth2_client: nil,
        request:
      )
      expect(second).to be_nil
    end.not_to change(PasswordRecoveryRequest, :count)
    expect(first).to be_present
  end

  it 'does not add configured template recipients to security mail' do
    user = create_user(login: 'exclusive-user', email: 'exclusive@example.test')
    template = MailTemplate.find_by!(name: 'password_recovery')
    recipient = MailRecipient.create!(label: 'Archive', bcc: 'archive@example.test')
    MailTemplateRecipient.create!(mail_template: template, mail_recipient: recipient)

    recovery_request = described_class.run(
      user.login,
      locale: :en,
      oauth2_client: nil,
      request:
    )

    expect(recovery_request.mail_log.to).to eq(user.email)
    expect(recovery_request.mail_log.cc).to eq('')
    expect(recovery_request.mail_log.bcc).to eq('')
  end

  it 'reuses the durable result when a worker retries after delivery' do
    user = create_user(login: 'retry-user', email: 'retry@example.test')
    submission = PasswordRecoverySubmission.enqueue!(
      identifier: user.email,
      locale: :en,
      oauth2_client: nil,
      request:
    )

    first = described_class.run(
      user.email,
      locale: :en,
      oauth2_client: nil,
      request:,
      submission:
    )

    expect do
      second = described_class.run(
        user.email,
        locale: :en,
        oauth2_client: nil,
        request:,
        submission:
      )
      expect(second).to eq(first)
    end.not_to change(PasswordRecoveryRequest, :count)
  end
end
