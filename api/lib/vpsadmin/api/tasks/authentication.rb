module VpsAdmin::API::Tasks
  class Authentication < Base
    # Close expired authentication processes
    #
    # Accepts the following environment variables:
    # [EXECUTE]: The authentication processes are closed only when set to 'yes'
    def close_expired
      ::AuthToken.joins(:token).includes(:token).where(
        'tokens.valid_to IS NOT NULL AND tokens.valid_to < ?',
        Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |t|
        puts "Token ##{t.id} valid_to=#{t.valid_to} token=#{t}"
        next if ENV['EXECUTE'] != 'yes'

        ActiveRecord::Base.transaction do
          VpsAdmin::API::Operations::User::IncompleteLogin.run(
            t,
            :totp,
            'authentication token expired'
          )
          t.destroy!
        end
      end

      ::Oauth2Authorization
        .joins(:code)
        .where(user_session: nil)
        .where('tokens.valid_to < ?', Time.now)
        .each do |auth|
        puts "OAuth2 authorization #{auth.id} valid_to=#{auth.code.valid_to} code=#{auth.code.token}"
        next if ENV['EXECUTE'] != 'yes'

        auth.destroy!
      end
    end
  end
end
