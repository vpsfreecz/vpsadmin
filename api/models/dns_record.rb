require 'ipaddress'
require_relative 'confirmable'

class DnsRecord < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  validates :record_type, presence: true, inclusion: { in: %w[A AAAA CNAME MX NS PTR SRV TXT] }
  validates :content, presence: true
  validate :check_name
  validate :check_content

  protected

  # rubocop:disable Style/GuardClause

  def check_name
    if !%w[* @].include?(name) && /\A(?=.{1,253}\z)(?!-)(?!.*-\.)(?!.*\.\.)([*a-zA-Z0-9\-]{0,63}(?<!-)\.?)+\z/ !~ name
      errors.add(:name, 'invalid record name; it must be a domain name, * or @')
    end
  end

  def check_content
    case record_type
    when 'A'
      begin
        ip = IPAddress.parse(content)
      rescue ArgumentError
        errors.add(:content, 'must be a valid IPv4 address')
        return
      end

      unless ip.ipv4?
        errors.add(:content, 'must be an IPv4 address, not IPv6')
      end

    when 'AAAA'
      begin
        ip = IPAddress.parse(content)
      rescue ArgumentError
        errors.add(:content, 'must be a valid IPv6 address')
        return
      end

      unless ip.ipv6?
        errors.add(:content, 'must be an IPv6 address, not IPv4')
      end

    when 'CNAME', 'MX', 'NS', 'PTR'
      unless valid_fqdn?(content)
        errors.add(:content, 'must be a fully qualified domain name')
      end

    when 'SRV'
      priority, weight, port, domain = content.split(' ', 4)

      unless [priority, weight, port].all? { |v| v.to_i.to_s == v }
        errors.add(:content, 'SRV priority, weight and port must be numbers')
      end

      unless valid_fqdn?(domain)
        errors.add(:content, 'SRV target must be a fully qualified domain name')
      end

    when 'TXT'
      # pass
    end
  end

  # rubocop:enable Style/GuardClause

  def valid_fqdn?(v)
    /\A((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,63}\.\Z/ =~ v
  end
end
