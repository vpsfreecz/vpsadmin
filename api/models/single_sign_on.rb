class SingleSignOn < ActiveRecord::Base
  belongs_to :user
  belongs_to :token, dependent: :delete
  has_many :oauth2_authorizations, dependent: :nullify

  def usable?
    token && token.valid_to > Time.now \
      && user && %w[active suspended].include?(user.object_state)
  end

  # @param authorization [Oauth2Authorization]
  def authorization_revoked(authorization)
    close unless any_active_authorizations?(except_ids: [authorization.id])
  end

  # @param except_ids [Array<Integer>]
  def any_active_authorizations?(except_ids: [])
    active_auth = oauth2_authorizations.detect do |auth|
      !except_ids.include?(auth.id) && auth.active?
    end

    active_auth ? true : false
  end

  def close
    return unless token

    token.destroy!
    update!(token: nil)
  end
end
