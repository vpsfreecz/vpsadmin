require 'haveapi/client'
require 'highline/import'

module VpsAdmin
    module MailTemplates ; end
end

require_relative 'mail-templates/meta'
require_relative 'mail-templates/template'
require_relative 'mail-templates/translation'

def template(&block)
  VpsAdmin::MailTemplates::Meta.load(block)
end

module VpsAdmin
  module MailTemplates
    def self.install(api, version, username = nil, password = nil)
      templates = find_templates
      api = HaveAPI::Client::Client.new(api)

      username ||= ask('Username: ') { |q| q.default = nil }.to_s
      password ||= ask('Password: ') do |q|
        q.default = nil
        q.echo = false
      end.to_s

      api.authenticate(:basic, user: username, password: password)

      # Find existing templates
      languages = api.language.list
      tpl_translations = {}

      api.mail_template.list.each do |tpl|
        tpl_translations[tpl] = tpl.translation.list(meta: {includes: 'language'})
      end

      # Create or update templates
      templates.each do |tpl|
        puts "Template #{tpl.name}"
        tpl_exists = tpl_translations.detect { |k, _| k.name == tpl.name }

        if tpl_exists
          puts "  Exists, updating"
          api_tpl = tpl_exists[0]
          api_tpl.update(tpl.params)

        else
          puts "  Not found, creating"
          api_tpl = api.mail_template.create(tpl.params)
        end

        tpl.translations.each do |tr|
          puts "  #{tr.lang}.#{tr.format}"
          tr_exists = tpl_exists && tpl_exists[1].detect { |v| v.language.code == tr.lang }

          if tr_exists
            puts "    Exists, updating"
            api.mail_template(api_tpl.id).translation(tr_exists.id).update(tr.params)

          else
            puts "    Not found, creating"

            lang = languages.detect { |v| v.code == tr.lang }
            fail "language '#{tr.lang}' not found" unless lang

            tr_params = tr.params
            tr_params.update(language: lang.id)
            api_tpl.translation.create(tr_params)
          end
        end

        puts
      end

      puts "Done"
    end

    def self.root
      File.realpath(
          File.join(
              File.dirname(__FILE__),
              '..', '..'
          )
      )
    end

    def self.find_templates
      ret = []
      
      Dir.glob(File.join(root, 'templates', '*')).each do |tpl|
        next unless Dir.exists?(tpl)
        
        ret << Template.new(tpl)
      end
      
      ret
    end
  end
end
