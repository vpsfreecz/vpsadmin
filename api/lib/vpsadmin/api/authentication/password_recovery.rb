require 'base64'
require 'erb'
require 'json'
require 'resolv'
require 'uri'

module VpsAdmin::API
  class Authentication::PasswordRecovery
    include PasswordChanges::ClientInfo

    BASE_PATH = '/oauth2/password-reset'.freeze
    CSRF_COOKIE = :vpsadmin_password_recovery_csrf
    FLOW_COOKIE = :vpsadmin_password_recovery
    COMPLETION_COOKIE = :vpsadmin_password_recovery_completed
    COMPLETION_SHOWN_COOKIE = :vpsadmin_password_recovery_completion_shown

    I18N_KEYS = %i[
      back_to_sign_in
      change_password
      complete
      continue
      continue_to_service
      continue_to_service_explanation
      email_sent
      email_sent_explanation
      hide_passwords
      identifier
      invalid_heading
      invalid_link
      invalid_session
      invalid_totp_code
      login
      mfa_explanation_totp
      mfa_explanation_webauthn
      mfa_explanation_totp_webauthn
      mfa_heading
      new_password
      password_heading
      password_too_short
      passwords_do_not_match
      passkey
      passkey_failed
      passkey_start_failed
      recovery_unavailable
      repeat_new_password
      request_new_link
      request_explanation
      request_heading
      send_email
      show_passwords
      sign_out_all
      signing_in_passkey
      temporarily_unavailable
      title
      too_many_requests
      too_many_totp_attempts
      totp_code
      verify_totp
    ].freeze

    class << self
      def i18n_keys
        I18N_KEYS.map { |key| "auth.password_recovery.#{key}" }
      end

      def configured_logo
        value = ::SysConfig.get(:core, :logo_url).to_s.strip
        return if value.empty?

        uri = URI.parse(value)
        return unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme)
        return if uri.host.blank? || uri.userinfo.present? || uri.fragment.present?

        { url: value, origin: uri.origin }
      rescue URI::InvalidURIError
        nil
      end

      def register_routes(sinatra)
        controller = self
        sinatra.before "#{BASE_PATH}*" do
          unless ::SysConfig.get(:core, :password_recovery_enabled)
            halt 404, VpsAdmin::API::I18n.t('errors.object_not_found')
          end

          logo = controller.configured_logo
          image_sources = ["'self'", logo&.fetch(:origin)].compact.join(' ')
          headers(
            'Cache-Control' => 'no-store, max-age=0',
            'Pragma' => 'no-cache',
            'Referrer-Policy' => 'no-referrer',
            'X-Frame-Options' => 'DENY',
            'X-Content-Type-Options' => 'nosniff',
            'Content-Security-Policy' => "default-src 'none'; " \
                                         "style-src 'unsafe-inline'; " \
                                         "script-src 'unsafe-inline'; " \
                                         "img-src #{image_sources}; " \
                                         "connect-src 'self'; form-action 'self'; " \
                                         "base-uri 'none'; frame-ancestors 'none'"
          )
        end

        sinatra.get(BASE_PATH) { controller.new(self).request_form }
        sinatra.post(BASE_PATH) { controller.new(self).request_submit }
        sinatra.get("#{BASE_PATH}/sent") { controller.new(self).sent }
        sinatra.get("#{BASE_PATH}/continue") { controller.new(self).landing }
        sinatra.post("#{BASE_PATH}/continue") { controller.new(self).exchange }
        sinatra.get("#{BASE_PATH}/verify") { controller.new(self).verify }
        sinatra.post("#{BASE_PATH}/verify/totp") { controller.new(self).verify_totp }
        sinatra.post("#{BASE_PATH}/verify/webauthn/begin") do
          controller.new(self).webauthn_begin
        end
        sinatra.post("#{BASE_PATH}/verify/webauthn/finish") do
          controller.new(self).webauthn_finish
        end
        sinatra.get("#{BASE_PATH}/password") { controller.new(self).password_form }
        sinatra.post("#{BASE_PATH}/password") { controller.new(self).password_submit }
        sinatra.get("#{BASE_PATH}/complete") { controller.new(self).complete }
      end
    end

    def initialize(handler)
      @handler = handler
      @request = handler.request
      @params = handler.params
    end

    def request_form
      render(:request, oauth2_client: requested_client)
    end

    def request_submit
      verify_csrf!
      client = requested_client

      result = ::PasswordRecoverySubmission.enqueue!(
        identifier: @params['identifier'],
        locale:,
        oauth2_client: client,
        request: @request
      )

      if result.rate_limited?
        @handler.headers('Retry-After' => result.retry_after.to_s)
        return render(
          :request,
          oauth2_client: client,
          error: text(:too_many_requests),
          status: 429
        )
      elsif !result.accepted?
        return render(
          :request,
          oauth2_client: client,
          error: text(:temporarily_unavailable),
          status: 503
        )
      end

      redirect_to(
        "#{BASE_PATH}/sent",
        client_id: client&.client_id,
        ui_locales: @params['ui_locales']
      )
    rescue StandardError => e
      warn "[vpsAdmin API] Password recovery request failed: #{e.class}: #{e.message}"
      render(
        :request,
        oauth2_client: client,
        error: text(:temporarily_unavailable),
        status: 503
      )
    end

    def sent
      render(:sent, oauth2_client: requested_client)
    end

    def landing
      render(:landing, oauth2_client: requested_client)
    end

    def exchange
      recovery_context = ::PasswordRecovery.find_any_by_email_token(@params['token'].to_s)
      use_recovery_context(recovery_context)
      verify_csrf!(recovery: recovery_context)
      recovery = ::PasswordRecovery.find_by_email_token(@params['token'].to_s)
      session_token = nil

      if recovery
        ::PasswordRecovery.transaction do
          user = recovery.user
          user.lock!
          recovery.lock!

          if recovery.email_token_usable?
            if recovery_still_eligible?(recovery, require_mfa: true, lock_mfa: true)
              session_token = recovery.consume_email_token!
            else
              recovery.invalidate!
            end
          end
        end
      end

      if session_token
        set_flow_cookie(session_token)
        return redirect_to_flow("#{BASE_PATH}/verify", recovery:)
      end

      render(:invalid, recovery:, status: 400)
    end

    def verify
      recovery = current_recovery(require_mfa: true)
      return render(:invalid, status: 400) unless recovery
      return redirect_to_flow("#{BASE_PATH}/password", recovery:) if recovery.mfa_verified?

      render(:mfa, recovery:, mfa_methods: mfa_methods(recovery.user))
    end

    def verify_totp
      verify_csrf!(recovery: recovery_context_from_flow)
      recovery = current_recovery(require_mfa: true)
      return render(:invalid, status: 400) unless recovery
      return redirect_to_flow("#{BASE_PATH}/password", recovery:) if recovery.mfa_verified?

      result = Operations::Authentication::PasswordRecoveryTotp.run(
        recovery,
        @params['totp_code'].to_s,
        @request
      )

      if result.authenticated?
        redirect_to_flow("#{BASE_PATH}/password", recovery:)
      elsif result.failure_limit_exceeded?
        clear_flow_cookie
        render(
          :invalid,
          recovery:,
          error: text(:too_many_totp_attempts),
          status: 400
        )
      else
        render(
          :mfa,
          recovery: recovery.reload,
          mfa_methods: mfa_methods(recovery.user),
          error: text(:invalid_totp_code),
          status: 422
        )
      end
    end

    def webauthn_begin
      verify_json_csrf!(recovery: recovery_context_from_flow)
      recovery = current_recovery(require_mfa: true)
      return json_error(text(:invalid_link), 400) unless recovery && !recovery.mfa_verified?

      client_info = webauthn_client_info
      options = nil
      challenge = nil
      ::PasswordRecovery.transaction do
        user = recovery.user
        user.lock!
        recovery.lock!
        next unless recovery.session_usable? && !recovery.mfa_verified? &&
                    recovery_still_eligible?(recovery, require_mfa: true)

        credentials = user.webauthn_credentials.where(enabled: true).order(:id).lock
        next unless credentials.exists?

        options = WebAuthn::Credential.options_for_get(
          allow: credentials.pluck(:external_id),
          user_verification: 'discouraged'
        )
        challenge = create_webauthn_challenge!(
          recovery,
          options.challenge,
          client_info:
        )
      end
      return json_error(text(:passkey_start_failed), 422) unless challenge

      json_ok(
        challenge_token: challenge.token.token,
        options: options.as_json
      )
    rescue StandardError => e
      warn "[vpsAdmin API] Password recovery WebAuthn start failed: #{e.class}: #{e.message}"
      json_error(text(:passkey_start_failed), 422)
    end

    def webauthn_finish
      verify_json_csrf!(recovery: recovery_context_from_flow)
      recovery = current_recovery(require_mfa: true)
      return json_error(text(:invalid_link), 400) unless recovery && !recovery.mfa_verified?

      input = json_input
      return json_error(text(:passkey_failed), 422) unless input.is_a?(Hash)

      challenge = ::WebauthnChallenge.joins(:token).where(
        password_recovery: recovery,
        challenge_type: 'authentication',
        tokens: { token: input['challenge_token'] }
      ).take
      return json_error(text(:passkey_failed), 422) unless challenge

      public_key_credential = input['public_key_credential']
      public_key_credential = nil unless valid_webauthn_input?(public_key_credential)
      result = Operations::Authentication::PasswordRecoveryWebauthn.run(
        recovery,
        challenge,
        public_key_credential,
        @request
      )

      if result.error
        warn '[vpsAdmin API] Password recovery WebAuthn verification failed: ' \
             "#{result.error.class}: #{result.error.message}"
      end
      return json_error(text(:passkey_failed), 422) unless result.authenticated?

      json_ok(password_uri: flow_uri("#{BASE_PATH}/password", recovery:))
    rescue ArgumentError, ActiveRecord::RecordNotFound, WebAuthn::Error => e
      warn "[vpsAdmin API] Password recovery WebAuthn verification failed: #{e.class}: #{e.message}"
      json_error(text(:passkey_failed), 422)
    end

    def password_form
      recovery = current_recovery
      return render(:invalid, status: 400) unless recovery&.mfa_verified?

      render(:password, recovery:)
    end

    def password_submit
      verify_csrf!(recovery: recovery_context_from_flow)
      recovery = current_recovery
      return render(:invalid, status: 400) unless recovery&.mfa_verified?

      password = @params['new_password'].to_s
      confirmation = @params['repeat_new_password'].to_s
      error =
        if password != confirmation
          text(:passwords_do_not_match)
        elsif password.length < 8
          text(:password_too_short)
        end
      return render(:password, recovery:, error:, status: 422) if error

      ::PasswordRecovery.transaction do
        user = recovery.user
        user.lock!
        recovery.lock!
        unless recovery.session_usable? && recovery.mfa_verified? &&
               recovery_still_eligible?(recovery, require_mfa: false)
          raise ActiveRecord::Rollback
        end

        user.set_password(
          password,
          source: :recovery,
          user_session: nil,
          **password_change_client_info(@request)
        )
        user.save!
        recovery.update!(completed_at: Time.current)
        ::TransactionChains::User::PasswordChanged.fire(user, @request)

        if @params['sign_out_all'] == '1'
          Operations::UserSession::CloseAll.run(user)
        end
      end

      unless recovery.reload.completed_at?
        clear_flow_cookie
        return render(:invalid, recovery:, status: 400)
      end

      recovery_request = recovery.password_recovery_request
      client = oauth2_client_for(recovery)
      completion_token = @handler.cookies[FLOW_COOKIE]
      clear_flow_cookie
      set_completion_cookie(completion_token)

      if client&.authorization_start_uri.present? &&
         !client.authorization_start_requires_user_action?
        return @handler.redirect(client.authorization_start_uri, 303)
      end

      redirect_to_flow(
        "#{BASE_PATH}/complete",
        recovery:
      )
    end

    def complete
      token = @handler.cookies[COMPLETION_COOKIE]
      recovery = token && ::PasswordRecovery.find_recently_completed_by_session_token(token)
      unless recovery
        clear_completion_cookies
        return render(:invalid, oauth2_client: requested_client, status: 400)
      end

      recovery_request = recovery.password_recovery_request
      use_persisted_locale(recovery_request.locale)
      client = oauth2_client_for(recovery)
      continuation_uri = client&.authorization_start_uri

      if continuation_uri.present?
        unless client.authorization_start_requires_user_action?
          return @handler.redirect(continuation_uri, 303)
        end

        continuation_host = URI.parse(continuation_uri).host
        if continuation_host.present?
          set_completion_shown_cookie(recovery.session_token_digest)
          return render(:complete, continuation_uri:, continuation_host:)
        end
      end

      clear_completion_cookies
      render(:complete)
    rescue URI::InvalidURIError
      clear_completion_cookies
      render(:complete)
    end

    protected

    def current_recovery(require_mfa: false)
      token = @handler.cookies[FLOW_COOKIE]
      return unless token

      recovery = ::PasswordRecovery.find_by_session_token(token)
      return clear_flow_cookie unless recovery

      @recovery_context = recovery
      effective_mfa_required = require_mfa && !recovery.mfa_verified?
      unless recovery.session_usable? &&
             recovery_still_eligible?(recovery, require_mfa: effective_mfa_required)
        recovery.invalidate!
        clear_flow_cookie
        return
      end

      recovery
    end

    def recovery_still_eligible?(recovery, require_mfa:, lock_mfa: false)
      user = recovery.user
      return false unless normalized_email(user.email) == normalized_email(recovery.email_snapshot)

      policy = password_recovery_policy(user, lock_mfa: lock_mfa && require_mfa)
      policy.eligible? && (!require_mfa || policy.effective_mfa?)
    end

    def mfa_methods(user)
      password_recovery_policy(user).mfa_methods
    end

    def mfa_explanation_key(methods)
      return :mfa_explanation_totp_webauthn if methods.include?(:totp) && methods.include?(:webauthn)
      return :mfa_explanation_totp if methods.include?(:totp)
      return :mfa_explanation_webauthn if methods.include?(:webauthn)

      :recovery_unavailable
    end

    def password_recovery_policy(user, lock_mfa: false)
      Operations::Authentication::PasswordRecoveryPolicy.run(user, @request, lock_mfa:)
    end

    def create_webauthn_challenge!(recovery, challenge_value, client_info:)
      ::Token.for_new_record!(2.minutes.from_now) do |token|
        recovery.webauthn_challenges.create!(
          user: recovery.user,
          token:,
          challenge_type: 'authentication',
          challenge: challenge_value,
          **client_info
        )
      end
    end

    def webauthn_client_info
      api_ip_addr = @request.ip
      api_ip_ptr = resolve_ptr(api_ip_addr)
      client_ip_addr = @request.env['HTTP_X_REAL_IP'] || api_ip_addr
      client_ip_ptr = client_ip_addr == api_ip_addr ? api_ip_ptr : resolve_ptr(client_ip_addr)

      {
        api_ip_addr:,
        api_ip_ptr:,
        client_ip_addr:,
        client_ip_ptr:,
        user_agent: ::UserAgent.find_or_create!(@request.user_agent.to_s),
        client_version: @request.user_agent.to_s
      }
    end

    def resolve_ptr(address)
      Resolv.new.getname(address)
    rescue Resolv::ResolvError
      address
    end

    def valid_webauthn_input?(value)
      return false unless value.is_a?(Hash)

      response = value['response'] || value[:response]
      return false unless response.is_a?(Hash)

      required_top = %w[id rawId type]
      required_response = %w[authenticatorData clientDataJSON signature]
      required_top.all? { |key| (value[key] || value[key.to_sym]).is_a?(String) } &&
        required_response.all? do |key|
          (response[key] || response[key.to_sym]).is_a?(String)
        end
    end

    def json_input
      @json_input ||= JSON.parse(@request.body.read)
    rescue JSON::ParserError
      {}
    end

    def json_ok(payload = {})
      @handler.content_type('application/json')
      JSON.dump({ status: true }.merge(payload))
    end

    def json_error(message, status)
      @handler.status(status)
      @handler.content_type('application/json')
      JSON.dump(status: false, message:)
    end

    def verify_json_csrf!(recovery: nil)
      return if csrf_valid?(@request.env['HTTP_X_CSRF_TOKEN'])

      use_recovery_context(recovery)
      @handler.halt(
        400,
        { 'Content-Type' => 'application/json' },
        JSON.dump(status: false, message: text(:invalid_session))
      )
    end

    def verify_csrf!(submitted = @params['csrf_token'], recovery: nil)
      return if csrf_valid?(submitted)

      use_recovery_context(recovery)
      @handler.halt(
        400,
        render(
          :invalid,
          recovery:,
          error: text(:invalid_session),
          status: 400
        )
      )
    end

    def csrf_valid?(submitted)
      cookie = @handler.cookies[CSRF_COOKIE]
      cookie.present? && submitted.present? &&
        cookie.bytesize == submitted.bytesize &&
        Rack::Utils.secure_compare(cookie, submitted)
    end

    def recovery_context_from_flow
      token = @handler.cookies[FLOW_COOKIE]
      return if token.blank?

      ::PasswordRecovery.find_any_by_session_token(token)
    end

    def use_recovery_context(recovery)
      return unless recovery

      @recovery_context = recovery
      use_persisted_locale(recovery.password_recovery_request.locale)
    end

    def csrf_token
      @csrf_token ||= @handler.cookies[CSRF_COOKIE].presence ||
                      ::PasswordRecovery.generate_token.tap do |token|
                        set_cookie(CSRF_COOKIE, token, max_age: 1.hour.to_i)
                      end
    end

    def set_flow_cookie(token)
      set_cookie(FLOW_COOKIE, token, max_age: ::PasswordRecovery::SESSION_LIFETIME.to_i)
    end

    def clear_flow_cookie
      @handler.response.delete_cookie(FLOW_COOKIE, cookie_options)
      nil
    end

    def set_completion_cookie(token)
      @handler.response.set_cookie(
        COMPLETION_COOKIE,
        value: token,
        path: '/',
        max_age: ::PasswordRecovery::COMPLETION_LIFETIME.to_i,
        httponly: true,
        secure: secure_cookie?,
        same_site: :lax
      )
    end

    def set_completion_shown_cookie(session_token_digest)
      @handler.response.set_cookie(
        COMPLETION_SHOWN_COOKIE,
        value: session_token_digest,
        path: '/',
        max_age: ::PasswordRecovery::COMPLETION_LIFETIME.to_i,
        httponly: true,
        secure: secure_cookie?,
        same_site: :lax
      )
    end

    def clear_completion_cookies
      [COMPLETION_COOKIE, COMPLETION_SHOWN_COOKIE].each do |name|
        @handler.response.delete_cookie(name, path: '/')
      end
      nil
    end

    def set_cookie(name, value, max_age:)
      @handler.response.set_cookie(
        name,
        cookie_options.merge(value:, max_age:, httponly: true)
      )
    end

    def cookie_options
      {
        path: BASE_PATH,
        secure: secure_cookie?,
        same_site: :strict
      }
    end

    def secure_cookie?
      uri = URI.parse(::SysConfig.get(:core, :auth_url).to_s)
      return true if uri.scheme == 'https'
      return false if uri.scheme == 'http'

      @request.secure?
    rescue URI::InvalidURIError
      @request.secure?
    end

    def requested_client
      client_id = @params['client_id'].to_s
      requested = ::Oauth2Client.find_by(client_id:) unless client_id.empty?
      requested || ::Oauth2Client.default_client
    end

    def use_persisted_locale(value)
      selected = value.to_s.downcase.to_sym
      @locale = if VpsAdmin::API::I18n.available_locales.include?(selected)
                  selected
                else
                  VpsAdmin::API::I18n::DEFAULT_LOCALE
                end
    end

    def locale
      @locale ||= begin
        candidates = @params['ui_locales'].to_s.split(/\s+/)
        candidates.concat(accept_language_candidates)
        available = VpsAdmin::API::I18n.available_locales.map(&:to_s)
        selected = candidates.filter_map do |candidate|
          normalized = candidate.to_s.downcase.tr('_', '-').sub(/\..*\z/, '')
          [normalized, normalized.split('-').first].find { |item| available.include?(item) }
        end.first
        (selected || VpsAdmin::API::I18n::DEFAULT_LOCALE).to_sym
      end
    end

    def accept_language_candidates
      @request.env.fetch('HTTP_ACCEPT_LANGUAGE', '').split(',').filter_map do |entry|
        tag, *options = entry.split(';').map(&:strip)
        next if tag.blank? || tag == '*'

        quality = options.filter_map { |option| option[/\Aq=([0-9.]+)\z/, 1]&.to_f }.first || 1.0
        [quality, tag] if quality > 0
      end.sort_by { |quality, _| -quality }.map(&:last)
    end

    def normalized_email(email)
      email.to_s.strip.downcase
    end

    def redirect_to(path, query = {})
      values = query.compact.reject { |_, value| value.to_s.empty? }
      target = values.empty? ? path : "#{path}?#{URI.encode_www_form(values)}"
      @handler.redirect(target, 303)
    end

    def redirect_to_flow(path, recovery: nil)
      @handler.redirect(flow_uri(path, recovery:), 303)
    end

    def flow_uri(path, recovery: nil)
      client = oauth2_client_for(recovery)
      selected_locale = recovery ? recovery.password_recovery_request.locale : locale
      values = {
        client_id: client&.client_id,
        ui_locales: selected_locale
      }.compact.reject { |_, value| value.to_s.empty? }

      values.empty? ? path : "#{path}?#{URI.encode_www_form(values)}"
    end

    def oauth2_client_for(recovery)
      if recovery
        return recovery.password_recovery_request.oauth2_client ||
               ::Oauth2Client.default_client
      end

      requested_client
    end

    def text(key, **values)
      ::I18n.with_locale(locale) do
        VpsAdmin::API::I18n.t("auth.password_recovery.#{key}", **values)
      end
    end

    def render(state, status: 200, **locals)
      recovery = locals[:recovery] || @recovery_context
      oauth2_client = if locals.has_key?(:oauth2_client)
                        locals[:oauth2_client]
                      else
                        oauth2_client_for(recovery)
                      end
      back_to_sign_in_uri = oauth2_client&.authorization_start_uri
      restart_uri = flow_uri(BASE_PATH, recovery:)
      landing_action_uri = flow_uri("#{BASE_PATH}/continue", recovery:)
      totp_action_uri = flow_uri("#{BASE_PATH}/verify/totp", recovery:)
      webauthn_begin_uri = flow_uri("#{BASE_PATH}/verify/webauthn/begin", recovery:)
      webauthn_finish_uri = flow_uri("#{BASE_PATH}/verify/webauthn/finish", recovery:)
      password_uri = flow_uri("#{BASE_PATH}/password", recovery:)
      continuation_uri = locals[:continuation_uri]
      continuation_host = locals[:continuation_host]
      mfa_methods = locals[:mfa_methods] || []
      mfa_explanation_key = mfa_explanation_key(mfa_methods)
      error = locals[:error]
      support_mail = ::SysConfig.get(:core, :support_mail).to_s
      logo_url = self.class.configured_logo&.fetch(:url)
      html_lang = locale.to_s
      t = ->(key, **values) { text(key, **values) }
      html_t = ->(key, **values) { Rack::Utils.escape_html(t.call(key, **values)) }
      js_t = ->(key, **values) { JSON.generate(t.call(key, **values)) }
      template = self.class.instance_variable_get(:@template) ||
                 self.class.instance_variable_set(
                   :@template,
                   ERB.new(File.read(File.join(__dir__, 'password_recovery.erb')), trim_mode: '-')
                 )

      @handler.status(status)
      @handler.content_type('text/html')
      ::I18n.with_locale(locale) { template.result(binding) }
    end
  end
end
