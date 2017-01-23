class ChangeRequest < UserRequest
  validates :change_reason, presence: true
  validates :full_name, length: {minimum: 2}, allow_blank: true
  validates :email, format: {
      with: /\A[^@]+@[a-zA-Z0-9_-]+\.[a-z]+\z/,
      message: 'not a valid e-mail address',
  }, allow_blank: true
  validate :check_changes

  def type_name
    'change'
  end

  def approve(chain, params)
    %i(full_name email address).each do |attr|
      v = send(attr)
      next unless v
      user.send("#{attr}=", v)
    end

    user.save!
  end

  protected
  def check_changes
    if !full_name && !email && !address
      errors.add(:full_name, 'change at least one parameter')
      errors.add(:email, 'change at least one parameter')
      errors.add(:address, 'change at least one parameter')
    end
  end
end
