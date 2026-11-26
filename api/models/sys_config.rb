class SysConfig < ApplicationRecord
  self.table_name = 'sysconfig'

  serialize :value, coder: JSON
  has_paper_trail only: [:value], on: [:update], if: ->(row) { IncidentEscalation::RULES.values.any? { |rule| rule.category == row.category } }
  validates :name, presence: true
  validates :category, format: {
    with: /\A[a-zA-Z0-9_]{1,75}\z/,
    message: 'bad format'
  }
  validates :name, format: {
    with: /\A[a-zA-Z0-9_]{1,75}\z/,
    message: 'bad format'
  }

  validate :validate_incident_escalation, if: -> { IncidentEscalation::RULES.values.any? { |rule| rule.category == category } && !new_record? && will_save_change_to_value? }
  validate :validate_choice_value, if: -> { new_record? || will_save_change_to_value? }

  # Declaration metadata is process-local; persisted values remain untouched.
  def self.label_registry
    @label_registry ||= {}
  end

  def display_label
    message = self.class.label_registry[self.class.localized_registration_key(category, name)]
    message ? HaveAPI.localize(message) : self[:label]
  end

  def self.choices_registry
    @choices_registry ||= {}
  end

  def self.normalize_choices(type, opts, existing)
    declaration = opts[:choices]
    return if declaration.nil?

    unless [String, Integer].include?(type) &&
           !cast_boolean(opts.fetch(:localized) { existing&.localized_config? })
      raise ArgumentError, 'choices require a nonlocalized String or Integer setting'
    end
    unless declaration.is_a?(Hash) && declaration.keys == [:values] &&
           declaration[:values].is_a?(Hash) && !declaration[:values].empty?
      raise ArgumentError, 'choices require a nonempty values map'
    end

    nullable = opts.fetch(:nullable, true)
    raise ArgumentError, 'choice nullability must be boolean' unless [true, false].include?(nullable)

    values = declaration[:values].to_h do |value, label|
      unless value.is_a?(type) && (type != Integer || value.abs <= 9_007_199_254_740_991)
        raise ArgumentError, 'choice values must match the setting type and be safe JSON scalars'
      end
      unless (label.is_a?(String) && !label.strip.empty?) ||
             (label.is_a?(HaveAPI::LocalizedMessage) && label.default.is_a?(String) && !label.default.strip.empty?)
        raise ArgumentError, 'choice labels require a string or localized message with an English default'
      end

      [value.is_a?(String) ? value.dup.freeze : value, label.is_a?(String) ? label.dup.freeze : label]
    end.freeze

    default = opts[:default]
    if (opts.has_key?(:default) || existing.nil?) &&
       !((default.nil? && nullable) || values.keys.any? { |value| value.eql?(default) })
      raise ArgumentError, 'choice default must be supported'
    end

    { values:, nullable: }.freeze
  end

  def choice_contract
    self.class.choices_registry[self.class.localized_registration_key(category, name)]
  end

  def choices
    choice_contract&.fetch(:values)&.map do |value, label|
      { value:, label: HaveAPI.localize(label) }
    end
  end

  def value_nullable
    choice_contract&.fetch(:nullable)
  end

  def choice_value_valid?(candidate)
    contract = choice_contract
    return true unless contract
    return contract[:nullable] if candidate.nil?

    contract[:values].keys.any? { |value| value.eql?(candidate) }
  end

  def validate_choice_value
    return unless choice_contract

    errors.add(:value, :inclusion) unless choice_value_valid?(value)
  end

  def validate_incident_escalation
    values = self.class.where(category:).order(:id).lock.to_h { |row| [row.name, row.value] }.merge(name => value)
    rule = IncidentEscalation::RULES.values.find { |entry| entry.category == category }
    config = IncidentEscalation.config(values, policy_key: rule.key)
    invalid = VpsIncidentPolicy.where(policy_key: rule.key).where(
      'COALESCE(warning_limit_override, CAST(? AS SIGNED)) <= 0 OR COALESCE(stop_limit_override, CAST(? AS SIGNED)) < COALESCE(warning_limit_override, CAST(? AS SIGNED))',
      config[:warning] || rule.warning_limit,
      config[:stop] || rule.stop_limit,
      config[:warning] || rule.warning_limit
    ).exists?
    errors.add(:value, 'conflicts with existing per-VPS thresholds') if invalid
  rescue IncidentEscalation::InvalidConfiguration => e
    errors.add(:value, e.message)
  end

  def self.get(category, key)
    obj = find_by(category:, name: key)
    obj.value if obj
  end

  def self.localized_get(category, key, locale = nil)
    obj = find_by(category:, name: key)
    return unless obj
    return obj.value unless obj.localized_config?

    localized_value(obj.value, locale)
  end

  def self.localized_value(value, locale = nil)
    return value unless value.is_a?(Hash)

    locale_code = language_code(locale || ::I18n.locale)
    candidates = [
      locale_code,
      locale_code&.split('-')&.first,
      'en'
    ].compact.uniq

    candidates.each do |code|
      localized = value[code] || value[code.to_sym]
      return localized if localized.present?
    end

    value.values.find(&:present?) || ''
  end

  def self.language_code(locale)
    case locale
    when ::Language
      locale.code.to_s
    else
      locale.to_s.tr('_', '-')
    end
  end

  def self.localized_registry
    @localized_registry ||= {}
  end

  def self.localized_registration_key(category, name)
    "#{category}\0#{name}"
  end

  def self.localized_registered?(category, name)
    localized_registry[localized_registration_key(category, name)] == true
  end

  def self.cast_boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def self.localized_column_supported?
    column_names.include?('localized')
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    false
  end

  def self.set(category, key, _value)
    SysConfig.transaction do
      obj = find_by(category:, name: key)

      if obj
        obj.update!(value: v)
      else
        create!(
          category:,
          name: k.to_s,
          value: v
        )
      end
    end
  end

  # @param category [Symbol]
  # @param name [Symbol]
  # @param type [Object]
  # @param opts [Hash]
  # @option opts [String, HaveAPI::LocalizedMessage] label
  # @option opts [String] description
  # @option opts [String] default
  # @option opts [Integer] min_user_level
  # @option opts [Boolean] localized
  # @option opts [Hash] choices ordered values-to-labels map
  # @option opts [Boolean] nullable whether a choice setting accepts nil
  def self.register(category, name, type, opts = {})
    label = opts[:label]
    if label.is_a?(HaveAPI::LocalizedMessage)
      unless label.default.is_a?(String) && !label.default.strip.empty?
        raise ArgumentError, 'localized labels require a nonempty English default'
      end

      opts = opts.merge(label: label.default)
    end

    cfg = find_by(category:, name:)
    choices_registry[localized_registration_key(category, name)] = normalize_choices(type, opts, cfg)
    if label.is_a?(HaveAPI::LocalizedMessage)
      label_registry[localized_registration_key(category, name)] = label
    else
      label_registry.delete(localized_registration_key(category, name))
    end

    if opts.has_key?(:localized)
      localized_registry[localized_registration_key(category, name)] =
        cast_boolean(opts[:localized])
    end

    if cfg
      %i[label description min_user_level].each do |opt|
        next unless opts.has_key?(opt)

        cfg.send("#{opt}=", opts[opt]) if cfg.send(opt.to_s) != opts[opt]
      end

      if cfg.has_attribute?(:localized) && opts.has_key?(:localized)
        cfg[:localized] = cast_boolean(opts[:localized])
      end

      cfg.data_type = type.to_s if cfg.data_type != type.to_s

      cfg.save! if cfg.changed?

    else
      attrs = opts.clone
      localized = attrs.delete(:localized)
      attrs.delete(:choices)
      attrs.delete(:nullable)
      attrs[:category] = category
      attrs[:name] = name
      attrs[:data_type] = type.to_s
      attrs.delete(:default)
      attrs[:value] = opts[:default] if opts[:default]
      attrs[:localized] = cast_boolean(localized) if localized_column_supported?

      create!(attrs)
    end
  rescue ActiveRecord::StatementInvalid
    # The sysconfig refactoring migration has not been run yet
    warn 'Ignoring sysconfig registration as needed database migration has not ' \
         'been applied yet'
  end

  # Class-body registrations can inspect existing rows before loading finishes.
  def localized_config?
    if has_attribute?(:localized)
      self.class.cast_boolean(self[:localized])
    else
      self.class.localized_registered?(category, name)
    end
  end

  register :core, :api_url, String, min_user_level: 0,
                                    label: VpsAdmin::API::I18n.message('sysconfig.labels.core.api_url', default: 'API URL')
  register :core, :auth_url, String, min_user_level: 0,
                                     label: VpsAdmin::API::I18n.message('sysconfig.labels.core.auth_url', default: 'Authentication service URL')
  register :core, :support_mail, String, min_user_level: 0,
                                         label: VpsAdmin::API::I18n.message('sysconfig.labels.core.support_mail', default: 'Support email address')
  register :core, :snapshot_download_base_url, String,
           label: VpsAdmin::API::I18n.message('sysconfig.labels.core.snapshot_download_base_url', default: 'Snapshot download base URL')
  register :core, :totp_issuer, String, default: 'vpsAdmin', min_user_level: 99,
                                        label: VpsAdmin::API::I18n.message('sysconfig.labels.core.totp_issuer', default: 'TOTP issuer name')
  register :core, :webauthn_rp_name, String, default: 'vpsAdmin', min_user_level: 99,
                                             label: VpsAdmin::API::I18n.message('sysconfig.labels.core.webauthn_rp_name', default: 'WebAuthn service name')
  register :core, :password_recovery_enabled, Boolean, default: false, min_user_level: 99,
                                                       label: VpsAdmin::API::I18n.message('sysconfig.labels.core.password_recovery_enabled', default: 'Allow password recovery')
  register :core, :transaction_key, Text, min_user_level: 99,
                                          label: VpsAdmin::API::I18n.message('sysconfig.labels.core.transaction_key', default: 'Transaction signing key')
  register :core, :logo_url, String, min_user_level: 0,
                                     label: VpsAdmin::API::I18n.message('sysconfig.labels.core.logo_url', default: 'Logo URL')
  register :node, :public_key, Text,
           label: VpsAdmin::API::I18n.message('sysconfig.labels.node.public_key', default: 'Node public key')
  register :node, :private_key, Text,
           label: VpsAdmin::API::I18n.message('sysconfig.labels.node.private_key', default: 'Node private key')
  register :node, :key_type, String,
           label: VpsAdmin::API::I18n.message('sysconfig.labels.node.key_type', default: 'Node key type')
  register :core, :ipv4_ddns_url, String, min_user_level: 99,
                                          label: VpsAdmin::API::I18n.message('sysconfig.labels.core.ipv4_ddns_url', default: 'IPv4 dynamic DNS URL')
  register :core, :ipv6_ddns_url, String, min_user_level: 99,
                                          label: VpsAdmin::API::I18n.message('sysconfig.labels.core.ipv6_ddns_url', default: 'IPv6 dynamic DNS URL')
  IncidentEscalation::RULES.each_value do |rule|
    register rule.category, :mode, String, default: 'observe', min_user_level: 99, nullable: false,
                                           label: VpsAdmin::API::I18n.message('sysconfig.labels.incident_policy.mode', default: 'Global policy mode'),
                                           choices: { values: {
                                           'observe' => VpsAdmin::API::I18n.message('sysconfig.choices.incident_mode.observe', default: 'Observation only'),
                                           'notify' => VpsAdmin::API::I18n.message('sysconfig.choices.incident_mode.notify', default: 'Warnings only'),
                                           'enforce' => VpsAdmin::API::I18n.message('sysconfig.choices.incident_mode.enforce', default: 'Warnings and automatic shutdown')
                                         } }
    register rule.category, :warning_limit, Integer, min_user_level: 99,
                                                     label: VpsAdmin::API::I18n.message('sysconfig.labels.incident_policy.warning_limit', default: 'Global warning threshold (7 days)'),
                                                     description: 'Global warning limit override. Null uses the limit declared in the policy.'
    register rule.category, :stop_limit, Integer, min_user_level: 99,
                                                  label: VpsAdmin::API::I18n.message('sysconfig.labels.incident_policy.stop_limit', default: 'Global shutdown threshold (30 days)'),
                                                  description: 'Global shutdown limit override. Null uses the limit declared in the policy.'
  end
  register :dns, :protected_zones, Array, min_user_level: 99,
                                          label: VpsAdmin::API::I18n.message('sysconfig.labels.dns.protected_zones', default: 'Protected DNS zones')

  def get_value
    case data_type
    when 'Hash', 'Array'
      YAML.dump(value)

    else
      value
    end
  end

  def localized
    localized_config?
  end

  def localized_value
    return unless localized_config?

    self.class.localized_value(value)
  end

  def set_value(v)
    if IncidentEscalation::RULES.values.any? { |rule| rule.category == category } && %w[warning_limit stop_limit].include?(name) && v == ''
      v = nil
    end
    if IncidentEscalation::RULES.values.any? { |rule| rule.category == category } && %w[warning_limit stop_limit].include?(name) && v.is_a?(String) && v.match?(/\A[0-9]+\z/)
      v = Integer(v, 10)
    end
    self.value = case data_type
                 when 'Hash', 'Array'
                   YAML.safe_load(v)

                 else
                   v
                 end
  end
end
