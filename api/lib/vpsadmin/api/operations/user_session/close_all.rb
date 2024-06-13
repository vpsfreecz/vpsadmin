require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::UserSession::CloseAll < Operations::Base
    # @param user [::User]
    # @param except [Array<::UserSession>, nil]
    def run(user, except: nil)
      q = user.user_sessions.where(closed_at: nil)
      q = q.where.not(id: except.map(&:id)) if except

      q.each do |user_session|
        Operations::UserSession::Close.run(user_session)
      end

      nil
    end
  end
end
