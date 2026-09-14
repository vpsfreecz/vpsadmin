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
                                 opts: { 'email' => user.email, 'service_name' => 'vpsAdmin API' })
    pending.update!(client_ip_addr: '192.0.2.90', client_ip_ptr: 'client.example.test',
                    user_agent: UserAgent.find_or_create!(
                      'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0'
                    ))
    request = build_request(extra_env: { 'HTTP_X_REAL_IP' => '192.0.2.90' })
    chain, = described_class.fire(pending, '123456', request)
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    mail = MailLog.find_by!(mail_template: template)
    expect(mail.to).to eq(user.email)
    expect(mail.cc).to eq('')
    expect(mail.bcc).to eq('')
    expect(mail.text_plain).to include('123456', '30 minutes', '192.0.2.90', 'support@example.test')
    expect(mail.text_plain).not_to include(pending.to_s)
    expect(mail.text_plain).to include('Device:', 'Linux', 'Firefox 128.0')
    expect(mail.text_plain).not_to include('Mozilla/5.0')
    expect(mail.text_html).to include('123456', 'vpsAdmin API', '192.0.2.90', 'client.example.test')
    expect(mail.text_html).not_to include(pending.to_s)
  end

  %w[en cs].each do |language|
    it "renders #{language} login details in both formats and escapes unrecognized clients in HTML" do
      user = create_lifecycle_user!
      user.update!(language: Language.find_by!(code: language))
      agent = 'CLI <script>alert("client")</script> & test'
      pending = create_auth_token!(user:, purpose: :email_login,
                                   opts: { 'email' => user.email, 'service_name' => 'Service <test> & API' })
      pending.update!(user_agent: UserAgent.find_or_create!(agent), client_ip_addr: '192.0.2.90', client_ip_ptr: '')
      request = build_request(ip: '198.51.100.20', user_agent: 'Different resend client')

      described_class.fire(pending, '012345', request)
      mail = MailLog.find_by!(user:, mail_template: MailTemplate.find_by!(name: 'user_login_email_verification'))
      expect(mail.text_plain).to include('012345', agent, 'Service <test> & API', '192.0.2.90')
      expect(mail.text_html).to include('012345', ERB::Util.html_escape(agent), 'Service &lt;test&gt; &amp; API')
      expect(mail.text_html).not_to include('<script>', '198.51.100.20', 'Different resend client')
      expect(mail.text_plain).not_to include('Requesting another code', 'Vyžádáním dalšího kódu')
    end
  end

  it 'fails closed if the mail template is missing' do
    user = create_lifecycle_user!
    pending = create_auth_token!(user:, purpose: :email_login,
                                 opts: { 'email' => user.email, 'service_name' => 'vpsAdmin API' })
    MailTemplate.find_by!(name: 'user_login_email_verification').destroy!
    expect { VpsAdmin::API::EmailLogin.deliver!(pending, '123456', build_request) }
      .to raise_error(VpsAdmin::API::EmailLogin::Error, 'email_login_unavailable')
  end
end
