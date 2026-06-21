module VpsAdmin
  module NotificationTemplates; end
end

require_relative 'notification_templates/cli'
require_relative 'notification_templates/meta'
require_relative 'notification_templates/template'
require_relative 'notification_templates/variant'
require_relative 'notification_templates/version'

def template(id = nil, &block)
  VpsAdmin::NotificationTemplates::Meta.load(id, block)
end

module VpsAdmin
  module NotificationTemplates
    def self.install(api)
      templates = find_templates

      languages = api.language.list
      existing_templates = {}
      existing_variants = {}

      api.notification_template.list.each do |tpl|
        existing_templates[tpl.name] = tpl
        existing_variants[tpl.name] = tpl.variant.list(meta: { includes: 'language' })
      end

      templates.each do |tpl|
        puts "Template #{tpl.name}" + (tpl.id == tpl.name ? '' : " (#{tpl.id})")
        api_tpl = existing_templates[tpl.name]

        if api_tpl
          puts '  Exists, updating'
          api_tpl.update(tpl.params)

        else
          puts '  Not found, creating'
          api_tpl = api.notification_template.create(tpl.params)
          existing_variants[tpl.name] = []
        end

        tpl.variants.each do |variant|
          puts "  #{variant.protocol}/#{variant.lang} (#{variant.formats.join(',')})"
          found = existing_variants.fetch(tpl.name).detect do |v|
            v.protocol == variant.protocol && v.language.code == variant.lang
          end

          if found
            puts '    Exists, updating'
            api.notification_template(api_tpl.id).variant(found.id).update(variant.params)

          else
            puts '    Not found, creating'

            lang = languages.detect { |v| v.code == variant.lang }
            raise "language '#{variant.lang}' not found" unless lang

            params = variant.params
            params.update(language: lang.id)
            api_tpl.variant.create(params)
          end
        end

        puts
      end

      puts 'Done'
    end

    def self.find_templates
      base = File.join(Dir.pwd, 'templates')
      raise "#{base} does not exist" unless Dir.exist?(base)

      Dir.children(base).sort.filter_map do |entry|
        path = File.join(base, entry)
        next unless Dir.exist?(path)

        Template.new(path)
      end
    end
  end
end
