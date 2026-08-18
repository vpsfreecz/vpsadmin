require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::UserSession::CloseAll < Operations::Base
    # @param user [::User]
    # @param except [Array<::UserSession>, nil]
    def run(user, except: nil)
      ::UserSession.transaction do
        user.lock!
        except_ids = Array(except).map(&:id)
        q = user.user_sessions.where(closed_at: nil)
        q = q.where.not(id: except_ids) if except_ids.any?

        q.each do |user_session|
          Operations::UserSession::Close.run(user_session)
        end

        authorizations = user.oauth2_authorizations.where.not(code: nil)
        if except_ids.any?
          authorizations = authorizations.where(user_session_id: nil).or(
            authorizations.where.not(user_session_id: except_ids)
          )
        end
        authorizations.find_each do |authorization|
          code = authorization.code
          authorization.update!(code: nil)
          code.destroy!
        end

        kept_sso_ids = user.oauth2_authorizations
                           .where(user_session_id: except_ids)
                           .where.not(single_sign_on_id: nil)
                           .distinct
                           .pluck(:single_sign_on_id)
        single_sign_ons = user.single_sign_ons.where.not(token: nil)
        single_sign_ons = single_sign_ons.where.not(id: kept_sso_ids) if kept_sso_ids.any?
        single_sign_ons.find_each(&:close)

        user.auth_tokens.find_each(&:destroy!)
      end

      nil
    end
  end
end
