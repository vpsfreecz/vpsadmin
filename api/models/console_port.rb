class ConsolePort < ApplicationRecord
  belongs_to :vps

  # @param vps [::Vps]
  # @return [::ConsolePort]
  def self.reserve!(vps)
    where(vps: nil).order('port ASC').limit(10).each do |port|
      port.update!(vps:)
    rescue ActiveRecord::RecordNotUnique
      next
    else
      return port
    end

    raise 'No console port available'
  end

  def free!
    update!(vps: nil)
  end
end
