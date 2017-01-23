class RegistrationRequest < UserRequest
  belongs_to :os_template
  belongs_to :location
  belongs_to :language

  validates :login, :full_name, :email, :address, :year_of_birth, :os_template_id,
            :location_id, :currency, :language_id, presence: true
  validates :login, format: {
      with: /\A[a-zA-Z0-9\.\-]{2,63}\z/,
      message: 'not a valid login',
  }
  validates :full_name, length: {minimum: 2}
  validates :email, format: {
      with: /\A[^@]+@[a-zA-Z0-9_-]+\.[a-z]+\z/,
      message: 'not a valid e-mail address',
  }
  validate :check_login

  def user_mail
    email
  end

  def user_language
    language
  end

  def type_name
    'registration'
  end

  def approve(chain, params)
    new_user = ::User.new(
        login: login,
        full_name: full_name,
        address: address,
        email: email,
        language: language,
        level: 2,
        mailer_enabled: true,
    )
    new_user.set_password(generate_password)

    chain.use_chain(TransactionChains::User::Create, args: [
        new_user,
        true,
        params[:node] || ::Node.pick_by_location(location),
        os_template,
    ])
  end

  protected
  def generate_password
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
    (0..11).map { chars.sample }.join
  end

  def check_login
    return if persisted?
    user = ::User.exists?(login: login)
    req = self.class.exists?(
        state: self.class.states[:awaiting],
        login: login,
    )

    errors.add(:login, "is taken") if user || req
  end
end
