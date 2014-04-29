class User < ActiveRecord::Base
  self.table_name = 'members'
  self.primary_key = 'm_id'

  has_many :vpses, :foreign_key => :m_id

  alias_attribute :login, :m_nick
  alias_attribute :role, :m_level

  #acts_as_authentic do |c|
  #  c.login_field = :login
  #  c.crypted_password_field = :m_pass
  #  c.crypto_provider = Vpsadmin::VpsadminCryptoProvider
  #end

  has_paper_trail ignore: [
      :m_last_activity,
  ]

  ROLES = {
      1 => 'Poor user',
      2 => 'User',
      3 => 'Power user',
      21 => 'Admin',
      90 => 'Super admin',
      99 => 'God',
  }

  def first_name
    m_name.split(' ').first
  end

  def last_name
    m_name.split(' ').last
  end

  def full_name
    m_name.empty? ? m_nick : m_name
  end

  def last_request_at
    m_last_activity ? Time.at(m_last_activity) : 'never'
  end

  def password_valid?(raw_password)
    Vpsadmin::VpsadminCryptoProvider.matches?(m_pass, m_nick, raw_password)
  end

  def self.find_by_username(login)
    find_by(m_nick: login)
  end
end
