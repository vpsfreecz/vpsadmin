module VpsAdmin::NotificationTemplates
  class Template
    attr_reader :id, :name, :variants, :meta

    def initialize(path)
      @path = path
      @name = File.basename(path)
      @variants = []

      meta_path = File.join(path, 'meta.rb')
      raise "#{meta_path} does not exist" unless File.exist?(meta_path)

      load meta_path

      @meta = Meta.last_meta
      Meta.reset_last

      @id = @meta[:id] || @name

      variant_files.each do |(protocol, code), files|
        @variants << Variant.new(self, protocol, code, files)
      end
    end

    def params
      visibility = @meta[:user_visibility]

      {
        template_id: @id,
        name: @name,
        label: @meta[:label] || '',
        user_visibility: if visibility.nil?
                           'default'
                         else
                           (visibility ? 'visible' : 'invisible')
                         end
      }
    end

    def variant_defaults(protocol, lang)
      @meta.variant_defaults(protocol, lang)
    end

    protected

    def variant_files
      files = {}

      Meta::PROTOCOLS.each do |protocol|
        protocol_dir = File.join(@path, protocol)
        next unless Dir.exist?(protocol_dir)

        Dir.glob(File.join(protocol_dir, '*.erb')).each do |file|
          parts = File.basename(file).split('.')
          raise "invalid template file #{file}" unless parts.length == 3 && parts.last == 'erb'

          lang = parts[0]
          format = parts[1]
          raise "invalid template format #{format} in #{file}" unless %w[subject text html].include?(format)

          files[[protocol, lang]] ||= []
          files[[protocol, lang]] << file
        end
      end

      files
    end
  end
end
