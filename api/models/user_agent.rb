require 'user_agent_parser'

class UserAgent < ApplicationRecord
  has_many :user_sessions
  has_many :user_failed_logins
  has_many :oauth2_authorizations

  def self.find_or_create!(user_agent)
    hash = Digest::SHA1.hexdigest(user_agent)
    find_by(agent_hash: hash) || create!(
      agent: user_agent,
      agent_hash: hash
    )
  end

  # @return [String]
  def to_user_friendly_s
    unknown =
      %i[os family device].map do |v|
        parsed.send(v).to_s
      end.all? do |v|
        v == 'Other'
      end

    return agent if unknown

    "#{parsed.os}, #{parsed.family} #{parsed.version} (#{parsed.device.family})"
  end

  # @return [UserAgentParser::UserAgent]
  def parsed
    @parsed ||= UserAgentParser.parse(agent)
  end
end
