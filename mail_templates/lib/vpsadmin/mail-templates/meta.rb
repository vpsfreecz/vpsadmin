module VpsAdmin::MailTemplates
  class Meta
    OPTS = %i[label from reply_to return_path subject user_visibility].freeze

    OPTS.each do |o|
      define_method(o) do |v|
        @opts[o] = v
      end
    end

    class << self
      attr_reader :last_meta

      def load(id, block)
        m = @last_meta = new(id)
        m.instance_exec(&block)
        m
      end

      def reset_last
        @last_meta = nil
      end
    end

    attr_reader :opts

    def initialize(id)
      @opts = { id: }
      @translations = {}
    end

    def lang(code, &)
      m = Meta.new(@opts[:id])
      m.instance_exec(&)

      @translations[code.to_s] = m.opts
    end

    def [](opt)
      @opts[opt]
    end

    def lang_opts(lang)
      ret = @opts.clone
      ret.update(@translations[lang]) if @translations[lang]
      ret
    end
  end
end
