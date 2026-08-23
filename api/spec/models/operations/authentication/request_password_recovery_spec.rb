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

  def create_user(login:, email:, mfa: true, oauth2: true, level: 1)
    create_lifecycle_user!(login:, email:).tap do |user|
      user.update!(
        enable_multi_factor_auth: mfa,
        enable_oauth2_auth: oauth2,
        level:
      )
      create_totp_device!(user:) if mfa
    end
  end

  it 'sends one account-neutral mail with one entry per matching login' do
    email = 'Shared.Address@example.test'
    client = create_oauth2_client!
    first = create_user(login: 'shared-a', email:)
    second = create_user(login: 'shared-b', email:, mfa: false)
    third = create_user(login: 'shared-c', email:, oauth2: false)
    administrator = create_user(login: 'shared-d', email:, mfa: false, level: 99)

    recovery_request = described_class.run(
      'shared.address@EXAMPLE.test',
      locale: :en,
      oauth2_client: client,
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
      [third.id, 'unavailable'],
      [administrator.id, 'unavailable']
    )

    body = recovery_request.mail_log.text_plain
    expect(body).to include(
      'Login: shared-a',
      'Login: shared-b',
      'Login: shared-c',
      'Login: shared-d'
    )
    normalized_body = body.gsub(/\s+/, ' ')
    expect(normalized_body).to include(
      'Password recovery is not available for administrator accounts. ' \
      'Ask another administrator to change the password.'
    )
    expect(body.scan(
      "/oauth2/password-reset/continue?client_id=#{client.client_id}&ui_locales=en#token="
    ).length).to eq(1)
    expect(body).not_to include('can be used once', 'recovery code')

    html = recovery_request.mail_log.text_html
    expect(html).to include(
      'Login: shared-a',
      'Login: shared-b',
      'Login: shared-c',
      'Login: shared-d'
    )
    expect(html).to include('class="action"', '>Set a new password</a>')
    expect(html).to include(
      'Password recovery is not available for administrator accounts. Ask'
    )
    expect(html.scan(
      "/oauth2/password-reset/continue?client_id=#{client.client_id}&amp;ui_locales=en#token="
    ).length).to eq(1)
    expect(html).not_to include('can be used once', 'recovery code')

    raw_token = body.match(/#token=([^\s]+)/)[1]
    recovery = recovery_request.password_recoveries.find_by!(user: first)
    expect(recovery.email_token_digest).to eq(PasswordRecovery.digest_token(raw_token))
    expect(recovery.email_token_digest).not_to eq(raw_token)
    expect(
      recovery_request.password_recoveries.find_by!(user: administrator)
    ).to have_attributes(email_token_digest: nil, email_expires_at: nil)
  end

  it 'uses the administrator message for support accounts with MFA' do
    support = create_user(
      login: 'support-recovery',
      email: 'support-recovery@example.test',
      level: 21
    )

    recovery_request = described_class.run(
      support.login,
      locale: :cs,
      oauth2_client: nil,
      request:
    )

    recovery = recovery_request.password_recoveries.find_by!(user: support)
    expect(recovery).to have_attributes(
      outcome: 'unavailable',
      email_token_digest: nil,
      email_expires_at: nil
    )
    normalized_body = recovery_request.mail_log.text_plain.gsub(/\s+/, ' ')
    expect(normalized_body).to include(
      'Obnovení hesla není pro administrátorské účty dostupné. ' \
      'O změnu hesla požádej jiného administrátora.'
    )
    expect(recovery_request.mail_log.text_plain).not_to include(
      '/oauth2/password-reset/continue',
      'nemá nastavené dvoufázové ověření'
    )
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

  it 'sends independent messages for logins sharing one primary email' do
    email = 'shared-throttle@example.test'
    first_user = create_user(login: 'shared-throttle-a', email:)
    second_user = create_user(login: 'shared-throttle-b', email:)

    expect do
      first = described_class.run(
        first_user.login,
        locale: :en,
        oauth2_client: nil,
        request:
      )
      second = described_class.run(
        second_user.login,
        locale: :en,
        oauth2_client: nil,
        request:
      )

      expect(first.password_recoveries.pluck(:user_id)).to eq([first_user.id])
      expect(second.password_recoveries.pluck(:user_id)).to eq([second_user.id])
      expect(first.mail_log.to).to eq(email)
      expect(second.mail_log.to).to eq(email)
    end.to change(PasswordRecoveryRequest, :count).by(2)
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
    ).submission

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
