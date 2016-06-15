module VpsAdmin::MailTemplates
  class Translation
    attr_reader :lang, :format, :plain, :html

    def initialize(tpl, file)
      @tpl = tpl
      parts = File.basename(file).split('.')

      @lang = parts[0]
      @format = parts[1]

      instance_variable_set("@#{@format}", File.read(file))
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
