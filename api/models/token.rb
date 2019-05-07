require 'securerandom'

class Token < ActiveRecord::Base
  belongs_to :owner, polymorphic: true

  # @param owner [ActiveRecord::Base]
  # @param valid_to [Time, nil]
  def self.for_new_record!(valid_to = nil)
    transaction do
      t = get!(valid_to)
      t.owner = yield(t)
      t.save!
      t.owner
    end
  end

  # @param valid_to [Time, nil]
  def self.get!(valid_to = nil)
    t = new(valid_to: valid_to)

    5.times do
      t.generate

      begin
        t.save!
        return t
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    fail 'unable to generate a unique token'
  end

  def generate
    self.token = SecureRandom.hex(50)
  end

  def to_s
    token
  end
end
