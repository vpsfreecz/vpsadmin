module VpsAdmin::MailTemplates
  class Meta
    OPTS = %i(label from reply_to return_path subject)

    OPTS.each do |o|
      define_method(o) do |v|
        @opts[o] = v
      end
    end

    class << self
      attr_reader :last_meta

      def load(block)
        m = @last_meta = new
        m.instance_exec(&block)
        m
      end

      def reset_last
        @last_meta = nil
      end
    end

    attr_reader :opts

    def initialize
      @opts = {}
      @translations = {}
    end

    def lang(code, &block)
      m = Meta.new
      m.instance_exec(&block)

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
