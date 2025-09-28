require 'securerandom'

class Uuid < ApplicationRecord
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
end
