module VpsAdmin::MailTemplates
  class Translation
    attr_reader :lang, :formats, :plain, :html

    def initialize(tpl, lang, files)
      @tpl = tpl
      @lang = lang
      @files = files
      @formats = []

      files.each do |f|
        parts = File.basename(f).split('.')
        instance_variable_set("@#{parts[1]}", File.read(f))

        @formats << parts[1] unless @formats.include?(parts[1])
      end

      @formats.sort!
    end

    def params
      ret = {
        text_plain: @plain,
        text_html: @html,
      }
      ret.update(@tpl.meta.opts)
      ret.update(@tpl.meta.lang_opts(@lang))
      ret
    end
  end
end
