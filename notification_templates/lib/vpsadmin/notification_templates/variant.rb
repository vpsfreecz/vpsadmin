module VpsAdmin::NotificationTemplates
  class Variant
    attr_reader :protocol, :lang, :formats

    def initialize(tpl, protocol, lang, files)
      @tpl = tpl
      @protocol = protocol
      @lang = lang
      @files = files
      @formats = []
      @content = {}

      files.each do |file|
        format = File.basename(file).split('.')[1]
        @content[format.to_sym] = File.read(file)
        @formats << format unless @formats.include?(format)
      end

      @formats.sort!
    end

    def params
      defaults = @tpl.variant_defaults(protocol, lang)

      {
        protocol:,
        from: defaults[:from],
        reply_to: defaults[:reply_to],
        return_path: defaults[:return_path],
        subject: @content[:subject] || defaults[:subject],
        text: @content[:text],
        html: @content[:html],
        options: defaults[:options] || {}
      }
    end
  end
end
