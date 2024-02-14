class SysConfig < ActiveRecord::Base
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
  def self.register(category, name, type, opts = {})
    cfg = find_by(category:, name:)

    if cfg
      %i[label description min_user_level].each do |opt|
        next unless opts.has_key?(opt)

        cfg.send("#{opt}=", opts[opt]) if cfg.send("#{opt}") != opts[opt]
      end

      cfg.data_type = type.to_s if cfg.data_type != type.to_s

      cfg.save! if cfg.changed?

    else
      attrs = opts.clone
      attrs[:category] = category
      attrs[:name] = name
      attrs[:data_type] = type.to_s
      attrs.delete(:default)
      attrs[:value] = opts[:default] if opts[:default]

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
  register :core, :transaction_key, Text, min_user_level: 99
  register :core, :logo_url, String, min_user_level: 0
  register :node, :public_key, Text
  register :node, :private_key, Text
  register :node, :key_type, String

  def get_value
    case data_type
    when 'Hash', 'Array'
      YAML.dump(value)

    else
      value
    end
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
