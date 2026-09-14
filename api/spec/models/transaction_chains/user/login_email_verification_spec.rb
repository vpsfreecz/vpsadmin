require 'spec_helper'

RSpec.describe TransactionChains::User::LoginEmailVerification do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    SysConfig.find_or_create_by!(category: 'core', name: 'support_mail').update!(value: 'support@example.test')
  end

  it 'queues the full message only to the primary mailbox regardless of notification preferences' do
    user = create_lifecycle_user!
    user.update!(mailer_enabled: false, enable_new_login_notification: false)
    template = MailTemplate.find_by!(name: 'user_login_email_verification')
    template.mail_recipients.create!(label: 'Unrelated recipients', to: 'alternate@example.test', cc: 'copy@example.test', bcc: 'blind@example.test')
    pending = create_auth_token!(user:, purpose: :email_login, valid_to: 30.minutes.from_now,
                                 opts: { 'email' => user.email })
    request = build_request(extra_env: { 'HTTP_X_REAL_IP' => '192.0.2.90' })
    chain, = described_class.fire(pending, '123456', request)
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    mail = MailLog.find_by!(mail_template: template)
    expect(mail.to).to eq(user.email)
    expect(mail.cc).to eq('')
    expect(mail.bcc).to eq('')
    expect(mail.text_plain).to include('123456', '30 minutes', '192.0.2.90', 'support@example.test')
    expect(mail.text_plain).not_to include(pending.to_s)
  end

  it 'fails closed if the mail template is missing' do
    user = create_lifecycle_user!
    pending = create_auth_token!(user:, purpose: :email_login, opts: { 'email' => user.email })
    MailTemplate.find_by!(name: 'user_login_email_verification').destroy!
    expect { VpsAdmin::API::EmailLogin.deliver!(pending, '123456', build_request) }
      .to raise_error(VpsAdmin::API::EmailLogin::Error, 'email_login_unavailable')
  end
end
