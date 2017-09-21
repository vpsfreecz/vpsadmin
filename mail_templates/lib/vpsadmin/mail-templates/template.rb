module VpsAdmin::MailTemplates
  class Template
    attr_reader :id, :name, :translations, :meta

    def initialize(path)
      @path = path
      @name = File.basename(path)
      @translations = []

      fail "#{path}/meta.rb does not exist" unless File.exists?(path)
      require_relative File.join(path, 'meta.rb')

      @meta = Meta.last_meta
      Meta.reset_last

      @id = @meta[:id] || @name

      langs = {}

      Dir.glob(File.join(path, '*.erb')).each do |tr|
        lang = File.basename(tr).split('.')[0]

        langs[lang] ||= []
        langs[lang] << tr
      end

      langs.each do |code, files|
        @translations << Translation.new(self, code, files)
      end
    end

    def params
      v = @meta[:user_visibility]

      {
          template_id: @id,
          name: @name,
          label: @meta[:label] || '',
          user_visibility: v.nil? ? 'default' : (v ? 'visible' : 'invisible'),
      }
    end
  end
end
