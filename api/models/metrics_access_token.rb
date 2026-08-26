class MetricsAccessToken < ApplicationRecord
  belongs_to :token, dependent: :delete
  belongs_to :user

  validates :metric_prefix,
            length: { maximum: 30 },
            format: { with: /\A[a-zA-Z_]+\z/, message: 'only allows letters and underscore' }

  # @param user [::User]
  # @param metric_prefix [String]
  # @return [MetricsAccessToken]
  def self.create_for!(user, metric_prefix)
    transaction do
      user.lock!
      unless user.authentication_allowed_by_lifecycle?
        raise ResourceLocked.new(user, 'user lifecycle change is pending')
      end

      access_token = new(user:, metric_prefix:)

      ::Token.for_new_record! do |token|
        access_token.token = token
        access_token.save!
        access_token
      end
    end
  end

  # @return [String]
  def access_token
    token.token
  end
end
