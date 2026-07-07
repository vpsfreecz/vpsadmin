class SysConfig < ApplicationRecord
  self.table_name = 'sysconfig'

  serialize :value, coder: JSON
  validates :name, presence: true
  validates :category, format: {
    with: /\A[a-zA-Z0-9_]{1,75}\z/,
    message: 'bad format'
  }
  validates :name, format: {
    with: /\A[a-zA-Z0-9_]{1,75}\z/,
    message: 'bad format'
  }

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
  # @option opts [String] label
  # @option opts [String] description
  # @option opts [String] default
  # @option opts [Integer] min_user_level
  # @option opts [Boolean] localized
  def self.register(category, name, type, opts = {})
    if opts.has_key?(:localized)
      localized_registry[localized_registration_key(category, name)] =
        cast_boolean(opts[:localized])
    end

    cfg = find_by(category:, name:)

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

  register :core, :api_url, String, min_user_level: 0
  register :core, :auth_url, String, min_user_level: 0
  register :core, :support_mail, String, min_user_level: 0
  register :core, :snapshot_download_base_url, String
  register :core, :totp_issuer, String, default: 'vpsAdmin', min_user_level: 99
  register :core, :webauthn_rp_name, String, default: 'vpsAdmin', min_user_level: 99
  register :core, :transaction_key, Text, min_user_level: 99
  register :core, :logo_url, String, min_user_level: 0
  register :node, :public_key, Text
  register :node, :private_key, Text
  register :node, :key_type, String
  register :core, :ipv4_ddns_url, String, min_user_level: 99
  register :core, :ipv6_ddns_url, String, min_user_level: 99
  register :dns, :protected_zones, Array, min_user_level: 99

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

  def localized_config?
    if has_attribute?(:localized)
      self.class.cast_boolean(self[:localized])
    else
      self.class.localized_registered?(category, name)
    end
  end

  def localized_value
    return unless localized_config?

    self.class.localized_value(value)
  end

  def set_value(v)
    self.value = case data_type
                 when 'Hash', 'Array'
                   YAML.safe_load(v)

                 else
                   v
                 end
  end
end
