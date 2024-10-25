require 'ipaddress'
require_relative 'confirmable'

class DnsRecord < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address
  belongs_to :update_token, class_name: 'Token', dependent: :delete

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  validates :record_type, presence: true, inclusion: { in: %w[A AAAA CNAME DS MX NS PTR SRV TXT] }
  validates :ttl, numericality: { in: (60..(7 * 86_400)) }, unless: -> { ttl.blank? }
  validates :priority, numericality: { in: (0..65_535) }, unless: -> { priority.blank? }
  validates :content, presence: true
  validates :comment, length: { maximum: 255 }
  validate :check_name
  validate :check_priority
  validate :check_content

  def dynamic_update_enabled
    !update_token_id.nil?
  end

  def dynamic_update_url
    return if update_token_id.nil?

    base_url =
      case record_type
      when 'A'
        ::SysConfig.get(:core, :ipv4_ddns_url)
      when 'AAAA'
        ::SysConfig.get(:core, :ipv6_ddns_url)
      else
        raise "Unsupported record type #{record_type.inspect}"
      end

    File.join(base_url, 'dns_records/dynamic_update/', update_token.token)
  end

  protected

  # rubocop:disable Style/GuardClause

  def check_name
    if !%w[* @].include?(name) && /\A(?=.{1,253}\z)(?!-)(?!.*-\.)(?!.*\.\.)([*a-zA-Z0-9\-]{0,63}(?<!-)\.?)+\z/ !~ name
      errors.add(:name, 'invalid record name; it must be a domain name, * or @')
    end
  end

  def check_priority
    if priority && !%w[MX SRV].include?(record_type)
      errors.add(:priority, 'only MX and SRV records can have priority set')
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

    when 'DS'
      check_ds_content

    when 'SRV'
      weight, port, domain = content.split(' ', 4)

      unless [weight, port].all? { |v| v.to_i.to_s == v }
        errors.add(:content, 'SRV weight and port must be numbers')
      end

      unless valid_fqdn?(domain)
        errors.add(:content, 'SRV target must be a fully qualified domain name')
      end

    when 'TXT'
      # pass
    end
  end

  DS_DIGEST_TYPES = {
    1 => { length: 40, type: 'SHA-1' },
    2 => { length: 64, type: 'SHA-256' },
    4 => { length: 96, type: 'SHA-384' }
  }.freeze

  def check_ds_content
    components = content.split

    if components.size != 4
      errors.add(:content, 'must have exactly four components: key tag, algorithm, digest type, and digest')
      return
    end

    key_tag, algorithm, digest_type_str, digest = components
    digest_type = digest_type_str.to_i

    unless key_tag =~ /\A\d+\z/
      errors.add(:content, 'invalid key tag: must be a numeric value')
    end

    unless algorithm =~ /\A\d+\z/
      errors.add(:content, 'invalid algorithm: must be a numeric value')
    end

    unless digest_type_str =~ /\A[124]\z/
      errors.add(
        :content,
        'invalid digest type: must be one of ' \
        "#{DS_DIGEST_TYPES.map { |k, v| "#{k} (#{v[:type]})" }.join(', ')}"
      )
    end

    digest_opts = DS_DIGEST_TYPES[digest_type]

    if digest_opts && (digest.length != digest_opts[:length] || digest !~ /\A[a-fA-F0-9]+\z/)
      errors.add(
        :content,
        "invalid digest: must be a #{digest_opts[:length]}-character hexadecimal " \
        "string for digest type #{digest_type_str} (#{digest_opts[:type]})"
      )
    end
  end

  # rubocop:enable Style/GuardClause

  def valid_fqdn?(v)
    /\A((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,63}\.\z/ =~ v
  end
end
