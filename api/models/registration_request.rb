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

  protected
  def check_login
    user = ::User.exists?(login: login)
    req = self.class.exists?(
        state: self.class.states[:awaiting],
        login: login,
    )

    errors.add(:login, "is taken") if user || req
  end
end
