require 'securerandom'

class Uuid < ApplicationRecord
  belongs_to :owner, polymorphic: true

  def self.generate!
    uuid = new

    10.times do
      uuid.uuid = SecureRandom.uuid

      begin
        uuid.save!
      rescue ActiveRecord::RecordNotUnique
        sleep(0.1)
        next
      else
        return uuid
      end
    end

    raise 'Unable to generate UUID'
  end

  # @yieldparam uuid [::Uuid]
  def self.generate_for_new_record!
    transaction do
      uuid = generate!
      uuid.owner = yield(uuid)
      uuid.save!
      uuid.owner
    end
  end
end
