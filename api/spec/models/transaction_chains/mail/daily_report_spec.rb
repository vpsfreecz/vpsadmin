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

    def report_password_change(source, user: SpecSeed.user, at: report_time - 10.minutes, client_ip_addr: nil)
      PasswordChangeLog.create!(user:, source:, created_at: at, client_ip_addr:)
    end

    def report_failed_login(user: SpecSeed.user, auth_type: 'password', reason: 'invalid password', at: report_time - 10.minutes,
                            client_ip_addr: nil)
      UserFailedLogin.create!(
        user:, auth_type:, reason:, created_at: at, client_ip_addr:,
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
      expect(statistics[:password_changes][:events]).to eq([])
      expect(statistics[:password_recoveries]).to eq(
        requests: 0, started: 0, completed: 0, unfulfilled: 0, expired: 0,
        invalidated: 0, no_mfa: 0, unavailable: 0,
        pending: { total: 0, email: 0, session: 0 }
      )
      expect(statistics[:failed_logins]).to eq(total: 0, users: 0, by_reason: [], events: [])
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
      changes = VpsAdmin::API::PasswordChanges::SOURCES.map { |source| report_password_change(source) }
      first = report_password_change(:recovery, at: report_start)
      report_password_change(:recovery, at: report_start - 1.second)
      report_password_change(:recovery, at: report_time)

      expect(statistics[:password_changes].except(:events)).to eq(
        total: 6,
        by_source: { 'authenticated' => 1, 'forced_reset' => 1, 'recovery' => 2, 'administrator' => 1, 'other' => 1 }
      )
      expect(statistics[:password_changes][:events].pluck(:id)).to eq([first.id] + changes.map(&:id))
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
      failures = [
        report_failed_login(at: report_start),
        report_failed_login,
        report_failed_login(user: SpecSeed.other_user),
        report_failed_login(auth_type: 'totp', reason: 'invalid totp code during password recovery'),
        report_failed_login(auth_type: 'webauthn', reason: 'authentication challenge expired')
      ]
      report_failed_login(at: report_start - 1.second)
      report_failed_login(at: report_time)

      expect(statistics[:failed_logins].except(:events)).to eq(
        total: 5, users: 2,
        by_reason: [
          { auth_type: 'password', reason: 'invalid password', total: 3, users: 2 },
          { auth_type: 'totp', reason: 'invalid totp code during password recovery', total: 1, users: 1 },
          { auth_type: 'webauthn', reason: 'authentication challenge expired', total: 1, users: 1 }
        ]
      )
      expect(statistics[:failed_logins][:events].pluck(:id)).to eq(failures.map(&:id))
    end

    it 'lists individual actions with only recorded client IPs and user identities' do
      change = report_password_change(:authenticated, client_ip_addr: '192.0.2.10')
      repeated_change = report_password_change(:authenticated, client_ip_addr: '192.0.2.10')
      failure = report_failed_login(client_ip_addr: '198.51.100.20')
      repeated_failure = report_failed_login

      common = { created_at: report_time - 10.minutes, user_id: SpecSeed.user.id, user_login: SpecSeed.user.login }
      expect(statistics[:password_changes][:events]).to eq(
        [change, repeated_change].map do |record|
          common.merge(id: record.id, source: 'authenticated', client_ip_addr: '192.0.2.10')
        end
      )
      expect(statistics[:failed_logins][:events]).to eq(
        [
          common.merge(id: failure.id, auth_type: 'password', reason: 'invalid password', client_ip_addr: '198.51.100.20'),
          common.merge(id: repeated_failure.id, auth_type: 'password', reason: 'invalid password', client_ip_addr: nil)
        ]
      )
      %i[password_changes failed_logins].each do |section|
        expect(statistics[section][:events].length).to eq(statistics[section][:total])
      end
    end

    it 'retains actions for users hidden by the default scope and missing user records' do
      change = report_password_change(:administrator, user: SpecSeed.other_user)
      failure = report_failed_login(user: SpecSeed.other_user)
      missing_user_id = User.unscoped.maximum(:id) + 1_000_000
      missing_change = report_password_change(:other).tap { |record| record.update_columns(user_id: missing_user_id) }
      missing_failure = report_failed_login.tap { |record| record.update_columns(user_id: missing_user_id) }
      SpecSeed.other_user.update_columns(object_state: 'hard_delete')

      expect(statistics[:password_changes][:events]).to contain_exactly(
        hash_including(id: change.id, user_id: SpecSeed.other_user.id, user_login: SpecSeed.other_user.login),
        hash_including(id: missing_change.id, user_id: missing_user_id, user_login: nil)
      )
      expect(statistics[:failed_logins][:events]).to contain_exactly(
        hash_including(id: failure.id, user_id: SpecSeed.other_user.id, user_login: SpecSeed.other_user.login),
        hash_including(id: missing_failure.id, user_id: missing_user_id, user_login: nil)
      )
    end

    it 'renders the report aggregates and accepts payloads from an older generator' do
      empty_statistics = VpsAdmin::API::DailyReportAuthentication.new(from: report_start, to: report_time).vars
      report_session(token_lifetime: 'permanent', admin: SpecSeed.admin)
      report_password_change(:authenticated, client_ip_addr: '192.0.2.10')
      report_failed_login(reason: '<script>example</script>', client_ip_addr: '198.51.100.20')
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
          'Password recovery activity', 'Recorded failed login attempts during period',
          'Password change details', 'Failed login details', '192.0.2.10', '198.51.100.20',
          "#{SpecSeed.user.login} (##{SpecSeed.user.id})", ':50:00'
        )
        if format == :html
          expect(rendered).to include('&lt;script&gt;example&lt;/script&gt;')
          expect(rendered).not_to include('<script>example</script>')
          expect(rendered).to include("href=\"https://webui.example.test/?page=adminm&amp;action=edit&amp;id=#{SpecSeed.user.id}\"")

          hostile_vars = vars.deep_dup
          hostile_vars[:password_changes][:events].first.merge!(
            user_login: '<action-user>', source: '<source>', client_ip_addr: '<ip"address>'
          )
          hostile_vars[:failed_logins][:events].first[:auth_type] = '<mechanism>'
          hostile_report = MailTemplateTranslation::TemplateBuilder.new(hostile_vars).build(source)
          expect(hostile_report).to include('&lt;action-user&gt;', '&lt;source&gt;', '&lt;ip&quot;address&gt;', '&lt;mechanism&gt;')
          expect(hostile_report).not_to include('<action-user>', '<source>', '<ip"address>', '<mechanism>')
        end
        visible = rendered.gsub(/<[^>]*>/, ' ').gsub(/\s+/, ' ')
        expect(visible).to match(/Manual password changes:? 1/)

        empty_report = MailTemplateTranslation::TemplateBuilder.new(vars.merge(empty_statistics)).build(source)
        expect(empty_report).to include('Permanent credentials: 0', 'Administrator-created sessions: 0')
        expect(empty_report).not_to include('Password change details', 'Failed login details')

        aggregate_vars = vars.merge(
          password_changes: vars[:password_changes].except(:events), failed_logins: vars[:failed_logins].except(:events)
        )
        aggregate_report = MailTemplateTranslation::TemplateBuilder.new(aggregate_vars).build(source)
        expect(aggregate_report).to include('Password changes during period', 'Recorded failed login attempts during period')
        expect(aggregate_report).not_to include('Password change details', 'Failed login details')

        missing_vars = vars.deep_dup
        %i[password_changes failed_logins].each do |section|
          missing_vars[section][:events].first.merge!(user_id: 987_654, user_login: nil, client_ip_addr: nil)
        end
        missing_report = MailTemplateTranslation::TemplateBuilder.new(missing_vars).build(source)
        expect(missing_report).to include('User #987654', '—')
        expect(missing_report).not_to include('action=edit&amp;id=987654', '192.0.2.10', '198.51.100.20')

        older_vars = vars.except(:user_sessions, :password_changes, :password_recoveries, :failed_logins)
        older_report = MailTemplateTranslation::TemplateBuilder.new(older_vars).build(source)
        expect(older_report).to include('Daily report').or include('daily report')
        expect(older_report).not_to include('User sessions', 'Password recovery activity')

        next unless ENV['VPSADMIN_TEST_DAILY_REPORT_PREVIEWS']

        directory = ENV.fetch('VPSADMIN_TEST_DAILY_REPORT_PREVIEWS')
        File.write(File.join(directory, "daily-report.#{format == :text ? 'txt' : 'html'}"), rendered)
        File.write(File.join(directory, "daily-report-older-payload.#{format == :text ? 'txt' : 'html'}"), older_report)
        File.write(File.join(directory, "daily-report-empty.#{format == :text ? 'txt' : 'html'}"), empty_report)
        File.write(File.join(directory, "daily-report-aggregate-only.#{format == :text ? 'txt' : 'html'}"), aggregate_report)
      end
    end
  end
end
