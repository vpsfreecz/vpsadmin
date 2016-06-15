module VpsAdmin::MailTemplates
  class Template
    attr_reader :name, :translations, :meta

    def initialize(path)
      @path = path
      @name = File.basename(path)
      @translations = []
    
      fail "#{path}/meta.rb does not exist" unless File.exists?(path)
      require_relative File.join(path, 'meta.rb')

      @meta = Meta.last_meta
      Meta.reset_last

      Dir.glob(File.join(path, '*.erb')).each do |tr|
        @translations << Translation.new(self, tr)
      end
    end

    def params
      {
          name: @name,
          label: @meta[:label] || '',
      }
    end
  end
end
