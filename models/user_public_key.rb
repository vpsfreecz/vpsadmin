class UserPublicKey < ActiveRecord::Base
  belongs_to :user
  has_paper_trail

  validates :label, :key, presence: true
  validates :label, length: {maximum: 255}
  validates :key, format: {
      with: /\A[^\n]+\z/,
      message: 'must not contain line breaks',
  }
  validates :key, length: {maximum: 5000}
  validate :process_key

  protected
  def process_key
    k = VpsAdmin::API::PublicKeyDecoder.new(key)

    self.comment = k.comment || ''
    self.fingerprint = k.fingerprint

  rescue => e
    errors.add(:key, 'invalid public key')
  end
end
