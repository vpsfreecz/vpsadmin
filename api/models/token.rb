require 'securerandom'

class Token < ApplicationRecord
  belongs_to :owner, polymorphic: true

  # @param owner [ActiveRecord::Base]
  # @param valid_to [Time, nil]
  # @param count [Integer] number of tokens to generate
  # @yieldparam [::Token] token
  # @yieldreturn [ActiveRecord::Base] owner
  # @return [ActiveRecord::Base] owner
  def self.for_new_record!(valid_to = nil, count: 1)
    transaction do
      tokens = count.times.map { get!(valid_to:) }
      owner = yield(*tokens)

      tokens.each do |t|
        t.owner = owner
        t.save!
      end

      owner
    end
  end

  # @param owner [ActiveRecord::Base]
  # @param valid_to [Time, nil]
  # @return [::Token]
  def self.get!(owner: nil, valid_to: nil)
    t = new(owner:, valid_to:)

    5.times do
      t.generate

      begin
        t.save!
        return t
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    raise 'unable to generate a unique token'
  end

  def generate
    self.token = SecureRandom.hex(50)
  end

  def regenerate!
    5.times do
      generate

      begin
        save!
        return
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    raise 'unable to generate a unique token'
  end

  def to_s
    token
  end
end
