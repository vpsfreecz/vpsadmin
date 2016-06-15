#!/usr/bin/env ruby

if RUBY_VERSION < '2.0'
  warn "Ruby version < 2.0 is not supported"
  exit(1)
end

require 'haveapi/client'
require 'highline/import'

if ARGV.count < 2
  warn "Usage: #{$0} <api url> <version> [username] [password]"
  exit(1)
end

def template(&block)
  Meta.load(block)
end

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

# Find available templates
templates = []

Dir.glob('*').each do |tpl|
  next unless Dir.exists?(tpl)
  
  templates << Template.new(tpl)
end

# Connect to the API
api = HaveAPI::Client::Client.new(ARGV[0])

username = ARGV[2] || ask('Username: ') { |q| q.default = nil }.to_s
password = ARGV[3] || ask('Password: ') do |q|
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
