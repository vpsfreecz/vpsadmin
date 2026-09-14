require 'securerandom'
require 'digest'
require 'mail'
require 'vpsadmin/api/exceptions'
require 'vpsadmin/api/operations/utils/dns'

module VpsAdmin::API
  # Email verification is a login step, independent of password reauthentication.
  module EmailLogin
    extend Operations::Utils::Dns

    LIFETIME = 30.minutes
    MAX_ATTEMPTS = 5
    MAX_SENDS = 3
    MAX_PENDING = 3
    RESEND_INTERVAL = 60
    BROWSER_COOKIE = :vpsadmin_email_login

    class Error < Exceptions::AuthenticationError; end

    Result = Data.define(:user, :auth_token, :error, :proof) do
      def success?
        error.nil?
      end
    end

    def self.required?(user, device: nil)
      user.enable_new_device_email_verification && !user.effective_multi_factor_auth? &&
        user.user_devices.where(known: true).exists? && !known_device?(user, device)
    end

    def self.known_device?(user, device)
      return false unless device

      current = ::UserDevice.includes(:token).find_by(id: device.id, user_id: user.id, known: true)
      current&.usable? == true
    end

    def self.valid_email?(email)
      return false unless email.is_a?(String) && email.bytesize <= 127 && !email.match?(/[\r\n]/)

      addresses = Mail::AddressList.new(email).addresses
      addresses.length == 1 && addresses.first.address == email &&
        addresses.first.local.present? && addresses.first.domain.to_s.include?('.')
    rescue Mail::Field::ParseError
      false
    end

    def self.masked_email(email)
      local, domain = email.to_s.split('@', 2)
      "#{local.to_s[0]}***@#{domain}"
    end

    def self.proof(user, method, device: nil)
      { 'generation' => user.authentication_generation, 'method' => method,
        'device_id' => device&.id }
    end

    # Recheck the bootstrap/device exception at the final issuance boundary.
    def self.check_authority!(user, evidence, device: nil)
      if evidence && evidence['generation'] != user.authentication_generation
        raise Error, 'email_login_expired'
      end

      if evidence && evidence['method'] == 'device' && device.nil?
        device = ::UserDevice.find_by(id: evidence['device_id'], user_id: user.id)
      end
      return unless required?(user, device:)
      return if evidence && %w[email mfa].include?(evidence['method'])

      raise Error, 'email_login_required'
    end

    def self.start(user, request:, context:, authentication_generation:, existing_token: nil, service_name: 'vpsAdmin API')
      raise Error, 'email_login_limited' unless ::EmailLoginRateLimit.available?(user, request, :send)

      client_ip_addr = request.env['HTTP_X_REAL_IP'].presence || request.ip
      client_ip_ptr = get_ptr(client_ip_addr)
      user.with_lock do
        raise Error, 'email_login_expired' unless user.authentication_generation == authentication_generation

        check_user!(user, context.fetch('flow'), request)
        raise Error, 'email_login_unavailable' unless valid_email?(user.email)

        pending = user.auth_tokens.joins(:token).where(purpose: :email_login)
                      .where('tokens.valid_to > ?', Time.current).count
        raise Error, 'email_login_limited' if pending >= MAX_PENDING

        auth_token = nil
        allowed = ::EmailLoginRateLimit.with_limits(user, request, :send) do |can_send|
          next false unless can_send

          code = format('%06d', SecureRandom.random_number(1_000_000))
          auth_token = ::Token.for_new_record!(Time.current + LIFETIME) do |token|
            ::AuthToken.create!(
              user:, token:, purpose: :email_login,
              user_agent: ::UserAgent.find_or_create!(request.user_agent.to_s),
              client_version: request.user_agent.to_s,
              api_ip_addr: request.ip, api_ip_ptr: '',
              client_ip_addr:,
              client_ip_ptr:,
              opts: { 'authentication_generation' => user.authentication_generation,
                      'email' => user.email, 'context' => context, 'service_name' => service_name,
                      'code_hash' => CryptoProviders::Bcrypt.encrypt(nil, code),
                      'attempts' => 0, 'sends' => 1, 'last_sent_at' => Time.current.to_i }
            )
          end
          deliver!(auth_token, code, request)
          existing_token&.destroy!
          true
        end
        raise Error, 'email_login_limited' unless allowed

        auth_token
      end
    end

    def self.process(token, request:, context:, code: nil, resend: false, cancel: false)
      found = ::AuthToken.joins(:token).find_by(tokens: { token: }, purpose: :email_login)
      raise Error, 'email_login_expired' unless found

      user = found.user
      user.with_lock do
        auth_token = ::AuthToken.where(id: found.id, purpose: :email_login).lock.take
        unless auth_token&.token_valid? && auth_token.authentication_current? &&
               auth_token.opts['email'] == user.email && auth_token.opts['context'] == context
          raise Error, 'email_login_expired'
        end

        check_user!(user, context.fetch('flow'), request)
        raise Error, 'email_login_expired' if user.effective_multi_factor_auth?

        if cancel
          auth_token.destroy!
          next Result.new(user:, auth_token: nil, error: nil, proof: nil)
        elsif resend
          next resend!(auth_token, request)
        end

        opts = auth_token.opts
        raise Error, 'email_login_expired' if opts.fetch('attempts') >= MAX_ATTEMPTS

        result = nil
        allowed = ::EmailLoginRateLimit.with_limits(user, request, :failure) do |can_check|
          next false unless can_check

          value = code.to_s.strip
          if value.match?(/\A[0-9]{6}\z/) && CryptoProviders::Bcrypt.matches?(opts['code_hash'], nil, value)
            evidence = proof(user, 'email')
            if user.password_reset
              auth_token.update!(purpose: :reset_password,
                                 opts: opts.except('code_hash').merge('email_login_proof' => evidence))
              auth_token.token.update!(valid_to: Time.current + 5.minutes)
            else
              auth_token.destroy!
            end
            result = Result.new(user:, auth_token:, error: nil, proof: evidence)
            yield result if block_given?
            false
          else
            opts['attempts'] += 1
            if opts['attempts'] >= MAX_ATTEMPTS
              auth_token.destroy!
            else
              auth_token.update!(opts:)
            end
            Operations::User::FailedLogin.run(user, :email, 'invalid email code', request)
            result = Result.new(user:, auth_token: auth_token.destroyed? ? nil : auth_token,
                                error: 'email_login_invalid', proof: nil)
            true
          end
        end
        result || Result.new(user:, auth_token:, error: allowed ? 'email_login_invalid' : 'email_login_limited',
                             proof: nil)
      end
    end

    def self.resend!(auth_token, request)
      opts = auth_token.opts
      if opts.fetch('sends') >= MAX_SENDS || Time.current.to_i - opts.fetch('last_sent_at') < RESEND_INTERVAL
        return Result.new(user: auth_token.user, auth_token:, error: 'email_login_resend_limited', proof: nil)
      end

      allowed = ::EmailLoginRateLimit.with_limits(auth_token.user, request, :send) do |can_send|
        next false unless can_send

        code = format('%06d', SecureRandom.random_number(1_000_000))
        deliver!(auth_token, code, request)
        auth_token.update!(opts: opts.merge(
          'code_hash' => CryptoProviders::Bcrypt.encrypt(nil, code),
          'sends' => opts['sends'] + 1, 'last_sent_at' => Time.current.to_i
        ))
        true
      end
      Result.new(user: auth_token.user, auth_token:, error: allowed ? nil : 'email_login_limited', proof: nil)
    end

    def self.check_user!(user, flow, request)
      enabled = case flow
                when 'oauth2' then user.enable_oauth2_auth
                when 'token' then user.enable_token_auth
                else false
                end
      raise Error, 'email_login_expired' unless enabled && user.enable_new_device_email_verification

      Operations::User::CheckLogin.run(user, request, allow_password_reset: true)
    end

    def self.deliver!(auth_token, code, request)
      ::TransactionChains::User::LoginEmailVerification.fire(auth_token, code, request)
    rescue Exceptions::MailTemplateDoesNotExist
      raise Error, 'email_login_unavailable'
    end
  end
end
