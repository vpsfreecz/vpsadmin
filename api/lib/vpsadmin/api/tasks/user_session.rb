module VpsAdmin::API::Tasks
  class UserSession < Base
    # Close expired user sessions
    #
    # Accepts the following environment variables:
    # [EXECUTE]: The sessions are closed only when set to 'yes'
    def close_expired
      ::SessionToken.joins(:token).includes(:user_sessions).where(
        'tokens.valid_to IS NOT NULL AND tokens.valid_to < ?',
        Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |t|
        puts "Token ##{t.id} valid_to=#{t.valid_to} token=#{t.token}"

        ::SessionToken.transaction do
          # There is never more than one user session
          t.user_sessions.each do |s|
            puts "  Close session ##{s.id}"
            next if ENV['EXECUTE'] != 'yes'

            s.update!(
              closed_at: t.valid_to,
              session_token: nil,
            )
          end

          t.destroy! if ENV['EXECUTE'] == 'yes'
        end
      end
    end
  end
end
