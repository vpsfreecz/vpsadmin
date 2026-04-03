require 'ipaddress'
require_relative 'confirmable'

class DnsRecord < ApplicationRecord
  RECORD_TYPES = %w[A AAAA CNAME DS MX NS PTR SRV SSHFP TLSA TXT].freeze

  TLSA_MATCHING_TYPES = {
    0 => { length: nil, type: 'Exact match' },
    1 => { length: 64, type: 'SHA-256' },
    2 => { length: 128, type: 'SHA-512' }
  }.freeze

  SSHFP_FINGERPRINT_TYPES = {
    1 => { length: 40, type: 'SHA-1' },
    2 => { length: 64, type: 'SHA-256' }
  }.freeze

  DS_DIGEST_TYPES = {
    1 => { length: 40, type: 'SHA-1' },
    2 => { length: 64, type: 'SHA-256' },
    4 => { length: 96, type: 'SHA-384' }
  }.freeze

  belongs_to :dns_zone
  belongs_to :host_ip_address
  belongs_to :user
  belongs_to :update_token, class_name: 'Token', dependent: :delete

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  validates :record_type, presence: true, inclusion: { in: RECORD_TYPES }
  validates :ttl, numericality: { in: (60..(7 * 86_400)) }, unless: -> { ttl.blank? }
  validates :priority, numericality: { in: (0..65_535) }, unless: -> { priority.blank? }
  validates :content, presence: true
  validates :comment, length: { maximum: 255 }
  validate :check_user
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

  def to_s
    "#{name} #{record_type}"
  end

  protected

  # rubocop:disable Style/GuardClause

  def check_user
    if dns_zone.user && user
      errors.add(:user_id, "user is set, but zone #{dns_zone.name} is owned (only records of system zones can have user set)")
    end
  end

  def check_name
    if !%w[* @].include?(name) && /\A(?=.{1,253}\z)(?!-)(?!.*-\.)(?!.*\.\.)([*a-zA-Z0-9\-_]{0,63}(?<!-)\.?)+\z/ !~ name
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

    when 'MX'
      check_mx_content

    when 'CNAME', 'NS', 'PTR'
      unless valid_fqdn?(content)
        errors.add(:content, 'must be a fully qualified domain name')
      end

    when 'DS'
      check_ds_content

    when 'SRV'
      check_srv_content

    when 'SSHFP'
      check_sshfp_content

    when 'TLSA'
      check_tlsa_content

    when 'TXT'
      # pass
    end
  end

  def check_ds_content
    return unless single_line_content?

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

  def check_mx_content
    return if null_mx_record? || valid_fqdn?(content)

    errors.add(:content, 'must be a fully qualified domain name or null record')
  end

  def check_tlsa_content
    return unless single_line_content?

    components = content.split

    if components.size != 4
      errors.add(
        :content,
        'must have exactly four components: usage, selector, matching type, and certificate association data'
      )
      return
    end

    usage, selector, matching_type_str, association_data = components

    unless usage =~ /\A\d+\z/
      errors.add(:content, 'invalid usage: must be a numeric value')
    end

    unless selector =~ /\A\d+\z/
      errors.add(:content, 'invalid selector: must be a numeric value')
    end

    unless matching_type_str =~ /\A[012]\z/
      errors.add(
        :content,
        'invalid matching type: must be one of ' \
        "#{TLSA_MATCHING_TYPES.map { |k, v| "#{k} (#{v[:type]})" }.join(', ')}"
      )
      return
    end

    matching_type = matching_type_str.to_i
    matching_opts = TLSA_MATCHING_TYPES[matching_type]

    case matching_type
    when 0
      unless association_data =~ /\A(?:[a-fA-F0-9]{2})+\z/
        errors.add(
          :content,
          'invalid certificate association data: must be a non-empty even-length hexadecimal ' \
          'string for matching type 0 (Exact match)'
        )
      end

    when 1, 2
      if association_data.length != matching_opts[:length] || association_data !~ /\A[a-fA-F0-9]+\z/
        errors.add(
          :content,
          "invalid certificate association data: must be a #{matching_opts[:length]}-character " \
          "hexadecimal string for matching type #{matching_type_str} (#{matching_opts[:type]})"
        )
      end
    end
  end

  def null_mx_record?
    priority == 0 && content == '.'
  end

  def check_srv_content
    weight, port, domain = content.split(' ', 4)

    unless [weight, port].all? { |v| v.to_i.to_s == v }
      errors.add(:content, 'SRV weight and port must be numbers')
    end

    return if null_srv_target?(domain) || valid_fqdn?(domain)

    errors.add(:content, 'SRV target must be a fully qualified domain name or .')
  end

  def null_srv_target?(domain)
    domain == '.'
  end

  def check_sshfp_content
    return unless single_line_content?

    components = content.split

    if components.size != 3
      errors.add(
        :content,
        'must have exactly three components: algorithm, fingerprint type, and fingerprint'
      )
      return
    end

    algorithm, fingerprint_type_str, fingerprint = components

    unless algorithm =~ /\A\d+\z/
      errors.add(:content, 'invalid algorithm: must be a numeric value')
    end

    unless fingerprint_type_str =~ /\A[12]\z/
      errors.add(
        :content,
        'invalid fingerprint type: must be one of ' \
        "#{SSHFP_FINGERPRINT_TYPES.map { |k, v| "#{k} (#{v[:type]})" }.join(', ')}"
      )
      return
    end

    fingerprint_type = fingerprint_type_str.to_i
    fingerprint_opts = SSHFP_FINGERPRINT_TYPES[fingerprint_type]

    if fingerprint.length != fingerprint_opts[:length] || fingerprint !~ /\A[a-fA-F0-9]+\z/
      errors.add(
        :content,
        "invalid fingerprint: must be a #{fingerprint_opts[:length]}-character hexadecimal " \
        "string for fingerprint type #{fingerprint_type_str} (#{fingerprint_opts[:type]})"
      )
    end
  end

  # rubocop:enable Style/GuardClause

  def single_line_content?
    return false if content.blank?
    return true unless content.match?(/[\r\n]/)

    errors.add(:content, 'must be a single-line value')
    false
  end

  def valid_fqdn?(v)
    /\A((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,63}\.\z/ =~ v
  end
end
