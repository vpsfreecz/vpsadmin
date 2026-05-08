# frozen_string_literal: true

require 'bundler/setup'
require 'rspec'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'zlib'

$:.unshift(File.expand_path('../lib', __dir__))

require 'vpsadmin/cli'

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
end

FakeRecord = Struct.new(:attrs, keyword_init: true) do
  def initialize(attrs = {})
    super(attrs: attrs)
  end

  def method_missing(name, *args)
    key = name.to_s.delete_suffix('=').to_sym

    if name.to_s.end_with?('=')
      attrs[key] = args.first
    elsif attrs.has_key?(key)
      attrs[key]
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    attrs.has_key?(name.to_s.delete_suffix('=').to_sym) || super
  end

  def attributes
    attrs
  end
end

class FakeCollection
  attr_reader :created, :deleted, :shown

  def initialize(records = [], show_records: {})
    @records = records
    @show_records = show_records
    @created = []
    @deleted = []
    @shown = []
  end

  def index(*)
    @records
  end

  alias list index

  def show(id, *)
    @shown << id
    @show_records.fetch(id) { @records.find { |r| r.id == id } }
  end

  def create(params)
    @created << params
    FakeRecord.new(params.merge(id: @created.length))
  end

  def delete(id)
    @deleted << id
  end
end

module ClientSpecIoHelpers
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new

    yield

    $stdout.string
  ensure
    $stdout = original
  end
end

RSpec.configure do |config|
  config.include ClientSpecIoHelpers
end
