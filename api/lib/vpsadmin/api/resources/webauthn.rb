require 'webauthn'

class VpsAdmin::API::Resources::Webauthn < HaveAPI::Resource
  route 'webauthn'

  module Utils
    def get_ptr(ip)
      Resolv.new.getname(ip)
    rescue Resolv::ResolvError => e
      e.message
    end

    def create_challenge!(user, challenge_type, challenge)
      api_ip_addr = request.ip
      api_ip_ptr = get_ptr(api_ip_addr)

      client_ip_addr = request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP'] || api_ip_addr
      client_ip_ptr = client_ip_addr == api_ip_addr ? api_ip_ptr : get_ptr(client_ip_addr)

      ::Token.for_new_record!(Time.now + 120) do |token|
        user.webauthn_challenges.create!(
          user:,
          token:,
          challenge_type:,
          challenge:,
          api_ip_addr:,
          api_ip_ptr:,
          client_ip_addr:,
          client_ip_ptr:,
          user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
          client_version: request.user_agent || ''
        )
      end
    end
  end

  class Registration < HaveAPI::Resource
    route 'registration'

    class Begin < HaveAPI::Action
      http_method :post

      output(:hash) do
        string :challenge_token
        custom :options
      end

      authorize { allow }

      include VpsAdmin::API::Resources::Webauthn::Utils

      def exec
        if current_user.webauthn_id.nil?
          current_user.update!(webauthn_id: WebAuthn.generate_user_id)
        end

        options = WebAuthn::Credential.options_for_create(
          user: { id: current_user.webauthn_id, name: current_user.login },
          exclude: current_user.webauthn_credentials.pluck(:external_id)
        )

        challenge = create_challenge!(current_user, 'registration', options.challenge)

        { challenge_token: challenge.token.token, options: options.as_json }
      end
    end

    class Finish < HaveAPI::Action
      http_method :post

      input(:hash) do
        string :challenge_token, required: true
        string :label, required: true
        custom :public_key_credential, required: true
      end

      authorize { allow }

      def exec
        challenge = ::WebauthnChallenge.joins(:token).where(
          user: current_user,
          tokens: { token: input[:challenge_token] },
          challenge_type: 'registration'
        ).take!

        error!('challenge token expired') unless challenge.token_valid?

        webauthn_credential = WebAuthn::Credential.from_create(input[:public_key_credential])

        begin
          webauthn_credential.verify(challenge.challenge)
        rescue WebAuthn::Error => e
          error!(e.message)
        end

        ActiveRecord::Base.transaction do
          current_user.webauthn_credentials.create!(
            label: input[:label],
            external_id: Base64.strict_encode64(webauthn_credential.raw_id),
            public_key: webauthn_credential.public_key,
            sign_count: webauthn_credential.sign_count
          )

          challenge.destroy!
        end

        ok!
      end
    end
  end

  class Authentication < HaveAPI::Resource
    route 'authentication'

    class Begin < HaveAPI::Action
      http_method :post
      auth false

      input(:hash) do
        string :auth_token, required: true
      end

      output(:hash) do
        string :challenge_token
        custom :options
      end

      authorize { allow }

      include VpsAdmin::API::Resources::Webauthn::Utils

      def exec
        auth_token = ::AuthToken.joins(:token).where(
          tokens: { token: input[:auth_token] },
          purpose: 'mfa'
        ).take!

        error!('auth token expired') unless auth_token.valid?

        options = WebAuthn::Credential.options_for_get(allow: auth_token.user.webauthn_credentials.where(enabled: true).pluck(:external_id))

        challenge = create_challenge!(auth_token.user, 'authentication', options.challenge)

        { challenge_token: challenge.token.token, options: options.as_json }
      end
    end

    class Finish < HaveAPI::Action
      http_method :post
      auth false

      input(:hash) do
        string :challenge_token, required: true
        string :auth_token, required: true
        custom :public_key_credential, required: true
      end

      authorize { allow }

      def exec
        challenge = ::WebauthnChallenge.joins(:token).where(
          tokens: { token: input[:challenge_token] },
          challenge_type: 'authentication'
        ).take!

        error!('challenge token expired') unless challenge.token_valid?

        auth_token = ::AuthToken.joins(:token).where(
          tokens: { token: input[:auth_token] },
          purpose: 'mfa',
          user: challenge.user
        ).take!

        error!('auth token expired') unless auth_token.token_valid?

        webauthn_credential = WebAuthn::Credential.from_get(input[:public_key_credential])

        stored_credential = challenge.user.webauthn_credentials.find_by!(
          external_id: Base64.strict_encode64(webauthn_credential.raw_id),
          enabled: true
        )

        begin
          webauthn_credential.verify(
            challenge.challenge,
            public_key: stored_credential.public_key,
            sign_count: stored_credential.sign_count
          )
        rescue WebAuthn::Error => e
          error!(e.message)
        end

        stored_credential.update!(
          sign_count: webauthn_credential.sign_count,
          last_use_at: Time.now
        )

        auth_token.update!(fulfilled: true)
        ok!
      end
    end
  end
end
