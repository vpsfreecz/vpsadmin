class SessionToken < ActiveRecord::Base
  belongs_to :user
  belongs_to :token, dependent: :delete
  has_many :user_sessions

  validates :user_id, presence: true

  enum lifetime: %i(fixed renewable_manual renewable_auto permanent)

  def self.custom!(attrs)
    st = new(
      user: attrs[:user],
      label: attrs[:label],
      lifetime: attrs[:lifetime],
      interval: attrs[:interval],
    )
    valid_to = st.lifetime != 'permanent' ? Time.now + st.interval : nil

    ::Token.for_new_record!(valid_to) do |token|
      st.token = token
      st.save!
      st
    end
  end

  def token_string
    token.to_s
  end

  def to_s
    token_string
  end

  def valid_to
    token.valid_to
  end

  def renew!
    token.update!(valid_to: Time.now + interval)
  end
end
