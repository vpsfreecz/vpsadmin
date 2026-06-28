module VpsAdmin::NotificationTemplates
  class Meta
    PROTOCOLS = %w[email telegram sms].freeze
    TEMPLATE_OPTS = %i[label user_visibility].freeze
    VARIANT_OPTS = %i[from reply_to return_path subject options].freeze

    TEMPLATE_OPTS.each do |name|
      define_method(name) { |value| @template_opts[name] = value }
    end

    VARIANT_OPTS.each do |name|
      define_method(name) { |value| @defaults[name] = value }
    end

    class << self
      attr_reader :last_meta

      def load(id, block)
        meta = @last_meta = new(id)
        meta.instance_exec(&block)
        meta
      end

      def reset_last
        @last_meta = nil
      end
    end

    attr_reader :id, :template_opts

    def initialize(id)
      @id = id
      @template_opts = {}
      @defaults = {}
      @language_defaults = {}
      @protocols = {}
    end

    def [](opt)
      return @id if opt == :id

      @template_opts[opt] || @defaults[opt]
    end

    def lang(code, &)
      context = VariantOptions.new
      context.instance_exec(&)
      @language_defaults[code.to_s] = context.opts
    end

    def protocol(name, &)
      protocol_name = name.to_s
      raise "unsupported template protocol '#{protocol_name}'" unless PROTOCOLS.include?(protocol_name)

      context = ProtocolOptions.new
      context.instance_exec(&)
      @protocols[protocol_name] = context
    end

    def variant_defaults(protocol, lang)
      protocol_meta = @protocols[protocol.to_s]
      @defaults
        .merge(@language_defaults.fetch(lang.to_s, {}))
        .merge(protocol_meta&.defaults || {})
        .merge(protocol_meta&.lang_opts(lang) || {})
    end
  end

  class VariantOptions
    attr_reader :opts

    def initialize
      @opts = {}
    end

    Meta::VARIANT_OPTS.each do |name|
      define_method(name) { |value| @opts[name] = value }
    end
  end

  class ProtocolOptions < VariantOptions
    attr_reader :defaults

    def initialize
      super
      @defaults = @opts
      @languages = {}
    end

    def lang(code, &)
      context = VariantOptions.new
      context.instance_exec(&)
      @languages[code.to_s] = context.opts
    end

    def lang_opts(code)
      @languages.fetch(code.to_s, {})
    end
  end
end
