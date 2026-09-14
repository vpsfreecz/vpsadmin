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
      :user_sessions,
      :password_changes,
      :password_recoveries,
      :failed_logins,
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
    expect(MailTemplate.templates[:daily_report][:vars]).to include(
      user_sessions: Hash, password_changes: Hash, password_recoveries: Hash, failed_logins: Hash
    )
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

      allow(MailTemplate).to receive(:send_mail!) do |_name, opts|
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

      allow(MailTemplate).to receive(:send_mail!) do |_name, opts|
        captured_vars = opts.fetch(:vars)
        build_mail_log_double
      end

      described_class.fire2(args: [SpecSeed.language])

      expect(captured_vars[:base_url]).to eq('https://webui.example.test')
    end
  end

  context 'with authentication statistics' do
    let(:report_time) { Time.utc(2026, 9, 14, 12) }
    let(:report_start) { report_time - 1.day }
    let(:statistics) { VpsAdmin::API::DailyReportAuthentication.new(from: report_start, to: report_time).vars }
    let(:recovery_request) do
      PasswordRecoveryRequest.create!(
        recipient_email: 'recovery@example.test', locale: 'en', created_at: report_time - 30.minutes
      )
    end

    before do
      UserSession.update_all(created_at: report_start - 1.day, closed_at: report_start)
      PasswordChangeLog.update_all(created_at: report_start - 1.day)
      UserFailedLogin.update_all(created_at: report_start - 1.day)
      User.where(id: [SpecSeed.user.id, SpecSeed.other_user.id]).update_all(
        object_state: 'active', lockout: false, password_reset: false,
        enable_token_auth: true, enable_oauth2_auth: true
      )
    end

    def report_session(user: SpecSeed.user, auth_type: 'token', created_at: report_time - 1.hour, **opts)
      create_open_session!(user:, auth_type:, valid_to: report_time + 1.hour, **opts).tap do |session|
        session.update_columns(created_at:)
      end
    end

    def report_recovery(**attrs)
      PasswordRecovery.create!({
        password_recovery_request: recovery_request,
        user: SpecSeed.user,
        email_snapshot: 'recovery@example.test',
        outcome: :recoverable,
        email_token_digest: SecureRandom.hex(32),
        email_expires_at: report_time + 30.minutes,
        created_at: report_time - 30.minutes
      }.merge(attrs))
    end

    def report_password_change(source, at: report_time - 10.minutes)
      PasswordChangeLog.create!(user: SpecSeed.user, source:, created_at: at)
    end

    def report_failed_login(user: SpecSeed.user, auth_type: 'password', reason: 'invalid password', at: report_time - 10.minutes)
      UserFailedLogin.create!(
        user:, auth_type:, reason:, created_at: at,
        api_ip_addr: '127.0.0.1', api_ip_ptr: 'localhost', client_version: 'RSpec'
      )
    end

    it 'returns zero counts and all known authentication types with no activity' do
      expect(statistics[:user_sessions][:created]).to eq(
        total: 0, users: 0,
        by_auth_type: %w[basic token oauth2].to_h { |type| [type, { total: 0, users: 0 }] }
      )
      expect(statistics[:user_sessions][:active][:total]).to eq(0)
      expect(statistics[:password_changes][:total]).to eq(0)
      expect(statistics[:password_recoveries]).to eq(
        requests: 0, started: 0, completed: 0, unfulfilled: 0, expired: 0,
        invalidated: 0, no_mfa: 0, unavailable: 0,
        pending: { total: 0, email: 0, session: 0 }
      )
      expect(statistics[:failed_logins]).to eq(total: 0, users: 0, by_reason: [])
    end

    it 'counts creations by type with independent user totals and half-open boundaries' do
      report_session(created_at: report_start).update_columns(closed_at: report_time - 30.minutes)
      report_session(auth_type: 'oauth2')
      report_session(auth_type: 'basic', user: SpecSeed.other_user).update_columns(closed_at: report_time - 1.hour)
      report_session(auth_type: 'legacy')
      report_session(created_at: report_start - 1.second)
      report_session(created_at: report_time)

      expect(statistics[:user_sessions][:created]).to eq(
        total: 4, users: 2,
        by_auth_type: {
          'basic' => { total: 1, users: 1 }, 'token' => { total: 1, users: 1 },
          'oauth2' => { total: 1, users: 1 }, 'legacy' => { total: 1, users: 1 }
        }
      )
      expect(statistics[:user_sessions][:active]).to include(total: 2, users: 1)
    end

    it 'counts permanent and administrator-created sessions as overlapping active subsets' do
      report_session(token_lifetime: 'permanent', admin: SpecSeed.admin, created_at: report_start - 1.day)
      report_session(user: SpecSeed.other_user, token_lifetime: 'permanent')
      report_session(admin: SpecSeed.admin)
      report_session(auth_type: 'oauth2')

      expect(statistics[:user_sessions][:active]).to include(total: 4, users: 2)
      expect(statistics[:user_sessions][:permanent]).to eq(total: 2, users: 2)
      expect(statistics[:user_sessions][:administrator_created]).to eq(total: 2, users: 1)
      expect(statistics[:user_sessions][:created][:total]).to eq(3)
    end

    it 'accounts for expiry and refresh tokens without waiting for cleanup or duplicating sessions' do
      client = create_oauth2_client!
      report_session.token.update!(valid_to: report_time - 1.second)
      report_session.token.update!(valid_to: nil) # Only permanent tokens allow no expiry.
      report_session.token.update!(valid_to: report_time) # Access-token comparison is inclusive.
      report_session.update_columns(closed_at: report_time - 1.minute)
      report_session(auth_type: 'basic')

      %i[valid_both expired_access missing_access expired_both boundary_refresh].each do |kind|
        session = report_session(auth_type: 'oauth2')
        create_oauth2_authorization!(
          user: SpecSeed.user, client:, user_session: session,
          refresh_valid_to: case kind
                            when :expired_both then report_time - 1.second
                            when :boundary_refresh then report_time
                            else report_time + 1.hour
                            end
        )
        session.token.update!(valid_to: report_time - 1.second) unless kind == :valid_both
        session.update!(token: nil) if kind == :missing_access
      end

      expect(statistics[:user_sessions][:active]).to include(total: 4, users: 1)
      expect(statistics[:user_sessions][:active][:by_auth_type]).to eq(
        'basic' => { total: 0, users: 0 }, 'token' => { total: 1, users: 1 },
        'oauth2' => { total: 3, users: 1 }
      )
    end

    it 'applies account restrictions and authentication flags to active sessions only' do
      report_session
      report_session(auth_type: 'oauth2')
      user = User.find(SpecSeed.user.id)
      [
        { lockout: true }, { password_reset: true }, { object_state: 'soft_delete' },
        { object_state: 'hard_delete' }, { enable_token_auth: false, enable_oauth2_auth: false }
      ].each do |restriction|
        previous = user.attributes.slice(*restriction.keys.map(&:to_s))
        user.update_columns(restriction)
        current = VpsAdmin::API::DailyReportAuthentication.new(from: report_start, to: report_time).vars
        expect(current[:user_sessions][:active][:total]).to eq(0)
        expect(current[:user_sessions][:created][:total]).to eq(2)
        user.update_columns(previous)
      end
    end

    it 'allows suspended users and applies the enable flags independently' do
      report_session
      report_session(auth_type: 'oauth2')
      User.where(id: SpecSeed.user.id).update_all(object_state: 'suspended', enable_token_auth: false)
      expect(statistics[:user_sessions][:active][:by_auth_type]).to eq(
        'basic' => { total: 0, users: 0 }, 'token' => { total: 0, users: 0 },
        'oauth2' => { total: 1, users: 1 }
      )
    end

    it 'counts password changes by source and reuses the recovery count' do
      VpsAdmin::API::PasswordChanges::SOURCES.each { |source| report_password_change(source) }
      report_password_change(:recovery, at: report_start)
      report_password_change(:recovery, at: report_start - 1.second)
      report_password_change(:recovery, at: report_time)

      expect(statistics[:password_changes]).to eq(
        total: 6,
        by_source: { 'authenticated' => 1, 'forced_reset' => 1, 'recovery' => 2, 'administrator' => 1, 'other' => 1 }
      )
      expect(statistics[:password_recoveries][:completed]).to eq(2)
    end

    it 'distinguishes one request from its account attempts and unavailable accounts' do
      report_recovery
      report_recovery(user: SpecSeed.other_user)
      report_recovery(outcome: :no_mfa, email_token_digest: nil, email_expires_at: nil)
      report_recovery(outcome: :unavailable, email_token_digest: nil, email_expires_at: nil)
      expect(statistics[:password_recoveries]).to include(
        requests: 1, started: 2, no_mfa: 1, unavailable: 1, unfulfilled: 0,
        pending: { total: 2, email: 2, session: 0 }
      )
    end

    it 'counts expiration at the applicable deadline and early invalidation once' do
      report_recovery(email_expires_at: report_time - 10.minutes)
      report_recovery(email_expires_at: report_time - 20.minutes, invalidated_at: report_time - 5.minutes)
      report_recovery(invalidated_at: report_time - 10.minutes)
      report_recovery(
        created_at: report_start - 1.hour, email_expires_at: report_start,
        invalidated_at: report_start + 1.minute
      )
      report_recovery(created_at: report_start - 2.hours, email_expires_at: report_start - 1.second)
      report_recovery(email_expires_at: report_time)
      report_recovery(
        email_expires_at: report_time - 20.minutes, email_consumed_at: report_time - 25.minutes,
        session_token_digest: SecureRandom.hex(32), session_expires_at: report_time - 5.minutes
      )
      report_recovery(
        email_expires_at: report_time - 10.minutes, completed_at: report_time - 20.minutes,
        invalidated_at: report_time - 20.minutes
      )
      report_password_change(:recovery, at: report_time - 20.minutes)

      expect(statistics[:password_recoveries]).to include(
        expired: 4, invalidated: 1, unfulfilled: 5, completed: 1,
        pending: { total: 0, email: 0, session: 0 }
      )
    end

    it 'keeps pending email and session stages separate and excludes future records' do
      report_recovery
      report_recovery(
        email_expires_at: report_time - 1.minute, email_consumed_at: report_time - 10.minutes,
        session_token_digest: SecureRandom.hex(32), session_expires_at: report_time + 5.minutes
      )
      report_recovery(created_at: report_time)
      report_recovery(created_at: report_time + 1.minute)
      expect(statistics[:password_recoveries]).to include(
        started: 2, unfulfilled: 0, pending: { total: 2, email: 1, session: 1 }
      )
    end

    it 'groups recorded failures by mechanism and reason while deduplicating users' do
      report_failed_login(at: report_start)
      report_failed_login
      report_failed_login(user: SpecSeed.other_user)
      report_failed_login(auth_type: 'totp', reason: 'invalid totp code during password recovery')
      report_failed_login(auth_type: 'webauthn', reason: 'authentication challenge expired')
      report_failed_login(at: report_start - 1.second)
      report_failed_login(at: report_time)

      expect(statistics[:failed_logins]).to eq(
        total: 5, users: 2,
        by_reason: [
          { auth_type: 'password', reason: 'invalid password', total: 3, users: 2 },
          { auth_type: 'totp', reason: 'invalid totp code during password recovery', total: 1, users: 1 },
          { auth_type: 'webauthn', reason: 'authentication challenge expired', total: 1, users: 1 }
        ]
      )
    end

    it 'renders the report aggregates and accepts payloads from an older generator' do
      empty_statistics = VpsAdmin::API::DailyReportAuthentication.new(from: report_start, to: report_time).vars
      report_session(token_lifetime: 'permanent', admin: SpecSeed.admin)
      report_password_change(:authenticated)
      report_failed_login(reason: '<script>example</script>')
      report_recovery
      chain = described_class.new
      vars = chain.call_hooks_for(
        :send, chain, args: [report_start, report_time], initial: chain.send(:vars, report_time)
      ).merge(base_url: 'https://webui.example.test/')
      text_template = File.expand_path('../../../../notification_templates/templates/daily_report/email/en.text.erb', __dir__)
      templates = { text: File.read(text_template) }
      if ENV['VPSADMIN_TEST_DAILY_REPORT_HTML']
        templates[:html] = File.read(ENV.fetch('VPSADMIN_TEST_DAILY_REPORT_HTML'))
      end

      templates.each do |format, source|
        rendered = MailTemplateTranslation::TemplateBuilder.new(vars).build(source)
        expect(rendered).to include(
          'User sessions', 'HTTP Basic', 'OAuth2', 'Permanent credentials: 1',
          'Administrator-created sessions: 1', 'Manual password changes',
          'Password recovery activity', 'Recorded failed login attempts during period'
        )
        if format == :html
          expect(rendered).to include('&lt;script&gt;example&lt;/script&gt;')
          expect(rendered).not_to include('<script>example</script>')
        end
        visible = rendered.gsub(/<[^>]*>/, ' ').gsub(/\s+/, ' ')
        expect(visible).to match(/Manual password changes:? 1/)

        empty_report = MailTemplateTranslation::TemplateBuilder.new(vars.merge(empty_statistics)).build(source)
        expect(empty_report).to include('Permanent credentials: 0', 'Administrator-created sessions: 0')

        older_vars = vars.except(:user_sessions, :password_changes, :password_recoveries, :failed_logins)
        older_report = MailTemplateTranslation::TemplateBuilder.new(older_vars).build(source)
        expect(older_report).to include('Daily report').or include('daily report')
        expect(older_report).not_to include('User sessions', 'Password recovery activity')

        next unless ENV['VPSADMIN_TEST_DAILY_REPORT_PREVIEWS']

        directory = ENV.fetch('VPSADMIN_TEST_DAILY_REPORT_PREVIEWS')
        File.write(File.join(directory, "daily-report.#{format == :text ? 'txt' : 'html'}"), rendered)
        File.write(File.join(directory, "daily-report-older-payload.#{format == :text ? 'txt' : 'html'}"), older_report)
        File.write(File.join(directory, "daily-report-empty.#{format == :text ? 'txt' : 'html'}"), empty_report)
      end
    end
  end
end
