class VpsConsole < ApplicationRecord
  belongs_to :user
  belongs_to :vps

  validates :token, uniqueness: true, length: { is: 100 }, unless: :token_nil?

  def self.find_for(vps, user)
    where(vps:, user:)
      .where('expiration > ?', Time.now)
      .where.not(token: nil)
      .take
  end

  def self.find_for!(vps, user)
    t = find_for(vps, user)

    raise ActiveRecord::RecordNotFound, 'Found no valid token' unless t

    t
  end

  def self.create_for!(vps, user)
    t = new(
      vps:,
      user:,
      expiration: Time.now + 60
    )

    tries = 5

    begin
      t.generate_token
      t.save!
    rescue ActiveRecord::RecordInvalid => e
      if tries > 0
        tries -= 1
        retry
      end

      raise e
    end

    t
  end

  def generate_token
    self.token = SecureRandom.hex(50)
  end

  def token_nil?
    token.nil?
  end
end
