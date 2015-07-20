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

class Template
  attr_reader :name

  def initialize(path)
    @path = path
    @name = File.basename(path)
   
    fail "#{path}/meta.rb does not exist" unless File.exists?(path)
    require_relative File.join(path, 'meta.rb')

    @meta = Meta.last_meta
    Meta.reset_last

    %i(plain html).each do |type|
      body_path = File.join(path, "#{type}.erb")
      next unless File.exists?(body_path)

      instance_variable_set("@#{type}", File.read(body_path))
    end
  end

  def params
    ret = {
        name: @name,
        text_plain: @plain,
        text_html: @html
    }
    ret.update(@meta.opts)
    ret
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
existing = api.mail_template.list

# Create or update templates
templates.each do |tpl|
  exists = existing.detect { |v| v.name == tpl.name }

  if exists
    puts "Update #{tpl.name}"
    api.mail_template.update(exists.id, tpl.params)

  else
    puts "Create #{tpl.name}"
    api.mail_template.create(tpl.params)
  end
end

puts "Done"

