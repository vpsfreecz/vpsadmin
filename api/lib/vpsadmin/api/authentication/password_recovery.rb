require 'base64'
require 'erb'
require 'json'
require 'resolv'
require 'uri'

module VpsAdmin::API
  class Authentication::PasswordRecovery
    BASE_PATH = '/oauth2/password-reset'.freeze
    CSRF_COOKIE = :vpsadmin_password_recovery_csrf
    FLOW_COOKIE = :vpsadmin_password_recovery

    I18N_KEYS = %i[
      back_to_sign_in
      change_password
      complete
      complete_explanation
      continue
      email_sent
      email_sent_explanation
      identifier
      invalid_link
      invalid_totp_code
      mfa_explanation
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
      request_explanation
      request_heading
      send_email
      signing_in_passkey
      sign_out_all
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
      render(:landing)
    end

    def exchange
      verify_csrf!
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
        return redirect_to("#{BASE_PATH}/verify")
      end

      render(:invalid, status: 400)
    end

    def verify
      recovery = current_recovery(require_mfa: true)
      return render(:invalid, status: 400) unless recovery
      return redirect_to("#{BASE_PATH}/password") if recovery.mfa_verified?

      render(:mfa, recovery:, mfa_methods: mfa_methods(recovery.user))
    end

    def verify_totp
      verify_csrf!
      recovery = current_recovery(require_mfa: true)
      return render(:invalid, status: 400) unless recovery
      return redirect_to("#{BASE_PATH}/password") if recovery.mfa_verified?

      result = Operations::Authentication::PasswordRecoveryTotp.run(
        recovery,
        @params['totp_code'].to_s,
        @request
      )

      if result.authenticated?
        redirect_to("#{BASE_PATH}/password")
      elsif result.failure_limit_exceeded?
        clear_flow_cookie
        render(:invalid, error: text(:too_many_totp_attempts), status: 400)
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
      verify_json_csrf!
      recovery = current_recovery(require_mfa: true)
      return json_error(text(:invalid_link), 400) unless recovery && !recovery.mfa_verified?

      credentials = recovery.user.webauthn_credentials.where(enabled: true)
      return json_error(text(:passkey_start_failed), 422) unless credentials.exists?

      options = WebAuthn::Credential.options_for_get(
        allow: credentials.pluck(:external_id),
        user_verification: 'discouraged'
      )
      challenge = create_webauthn_challenge!(recovery, options.challenge)

      json_ok(
        challenge_token: challenge.token.token,
        options: options.as_json
      )
    rescue StandardError => e
      warn "[vpsAdmin API] Password recovery WebAuthn start failed: #{e.class}: #{e.message}"
      json_error(text(:passkey_start_failed), 422)
    end

    def webauthn_finish
      verify_json_csrf!
      recovery = current_recovery(require_mfa: true)
      return json_error(text(:invalid_link), 400) unless recovery && !recovery.mfa_verified?

      input = json_input
      return json_error(text(:passkey_failed), 422) unless input.is_a?(Hash)

      challenge = ::WebauthnChallenge.joins(:token).where(
        password_recovery: recovery,
        challenge_type: 'authentication',
        tokens: { token: input['challenge_token'] }
      ).take
      return json_error(text(:passkey_failed), 422) unless challenge&.token_valid?

      public_key_credential = input['public_key_credential']
      return json_error(text(:passkey_failed), 422) unless valid_webauthn_input?(public_key_credential)

      credential = WebAuthn::Credential.from_get(
        stringify_keys(public_key_credential)
      )
      stored = recovery.user.webauthn_credentials.find_by!(
        external_id: Base64.strict_encode64(credential.raw_id),
        enabled: true
      )
      credential.verify(
        challenge.challenge,
        public_key: stored.public_key,
        sign_count: stored.sign_count
      )

      verified = false
      ::PasswordRecovery.transaction do
        recovery.lock!
        challenge.lock!

        if recovery.session_usable? && !recovery.mfa_verified? && challenge.token_valid?
          challenge.destroy!
          stored.update!(sign_count: credential.sign_count, last_use_at: Time.current)
          ::WebauthnCredential.increment_counter(:use_count, stored.id)
          recovery.update!(mfa_verified_at: Time.current)
          verified = true
        end
      end

      return json_error(text(:passkey_failed), 422) unless verified

      json_ok
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
      verify_csrf!
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

        user.set_password(password)
        user.save!
        recovery.update!(completed_at: Time.current)
        ::TransactionChains::User::PasswordChanged.fire(user, @request)

        if @params['sign_out_all'] == '1'
          Operations::UserSession::CloseAll.run(user)
        end
      end

      unless recovery.reload.completed_at?
        clear_flow_cookie
        return render(:invalid, status: 400)
      end

      client = recovery.password_recovery_request.oauth2_client
      clear_flow_cookie

      if client&.authorization_start_uri.present?
        @handler.redirect(client.authorization_start_uri, 303)
      else
        redirect_to("#{BASE_PATH}/complete")
      end
    end

    def complete
      render(:complete)
    end

    protected

    def current_recovery(require_mfa: false)
      token = @handler.cookies[FLOW_COOKIE]
      return unless token

      recovery = ::PasswordRecovery.find_by_session_token(token)
      return clear_flow_cookie unless recovery

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

    def password_recovery_policy(user, lock_mfa: false)
      Operations::Authentication::PasswordRecoveryPolicy.run(user, @request, lock_mfa:)
    end

    def create_webauthn_challenge!(recovery, challenge_value)
      api_ip_addr = @request.ip
      api_ip_ptr = resolve_ptr(api_ip_addr)
      client_ip_addr = @request.env['HTTP_CLIENT_IP'] ||
                       @request.env['HTTP_X_REAL_IP'] || api_ip_addr
      client_ip_ptr = client_ip_addr == api_ip_addr ? api_ip_ptr : resolve_ptr(client_ip_addr)

      ::Token.for_new_record!(2.minutes.from_now) do |token|
        recovery.webauthn_challenges.create!(
          user: recovery.user,
          token:,
          challenge_type: 'authentication',
          challenge: challenge_value,
          api_ip_addr:,
          api_ip_ptr:,
          client_ip_addr:,
          client_ip_ptr:,
          user_agent: ::UserAgent.find_or_create!(@request.user_agent.to_s),
          client_version: @request.user_agent.to_s
        )
      end
    end

    def resolve_ptr(address)
      Resolv.new.getname(address)
    rescue Resolv::ResolvError
      address
    end

    def stringify_keys(value)
      case value
      when Hash
        value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
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

    def verify_json_csrf!
      verify_csrf!(@request.env['HTTP_X_CSRF_TOKEN'])
    end

    def verify_csrf!(submitted = @params['csrf_token'])
      cookie = @handler.cookies[CSRF_COOKIE]
      valid = cookie.present? && submitted.present? &&
              cookie.bytesize == submitted.bytesize &&
              Rack::Utils.secure_compare(cookie, submitted)
      @handler.halt(400, text(:recovery_unavailable)) unless valid
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
      return if client_id.empty?

      ::Oauth2Client.find_by(client_id:)
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

    def text(key, **values)
      ::I18n.with_locale(locale) do
        VpsAdmin::API::I18n.t("auth.password_recovery.#{key}", **values)
      end
    end

    def render(state, status: 200, **locals)
      oauth2_client = locals[:oauth2_client]
      back_to_sign_in_uri = oauth2_client&.authorization_start_uri
      recovery = locals[:recovery]
      mfa_methods = locals[:mfa_methods] || []
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
