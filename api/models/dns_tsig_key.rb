class DnsTsigKey < ApplicationRecord
  belongs_to :user
  has_many :dns_zone_transfers, dependent: :restrict_with_exception

  validates :name, :algorithm, :secret, presence: true

  validates :name, format: {
    with: /\A[a-zA-Z0-9\-\.]+\Z/,
    message: '%{value} is not a valid TSIG key name'
  }

  validates :algorithm, inclusion: {
    in: %w[hmac-sha224 hmac-sha256 hmac-sha384 hmac-sha512],
    message: '%{value} is not a valid TSIG algorithm'
  }

  validate :check_secret

  protected

  def check_secret
    begin
      return if Base64.strict_encode64(Base64.strict_decode64(secret)) == secret
    rescue ArgumentError
      # pass
    end

    errors.add(:secret, 'not a valid base64 string')
  end
end
