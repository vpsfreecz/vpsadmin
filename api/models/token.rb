require 'securerandom'

class Token < ActiveRecord::Base
  belongs_to :owner, polymorphic: true

  # @param owner [ActiveRecord::Base]
  # @param valid_to [Time, nil]
  # @yieldparam [::Token] token
  # @yieldreturn [ActiveRecord::Base] owner
  # @return [ActiveRecord::Base] owner
  def self.for_new_record!(valid_to = nil)
    transaction do
      t = get!(valid_to:)
      t.owner = yield(t)
      t.save!
      t.owner
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
