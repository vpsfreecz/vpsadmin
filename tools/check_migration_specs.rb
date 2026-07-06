#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'open3'

options = {
  mode: :cached
}

MIGRATION_PATHS = [
  'api/db/migrate/*.rb',
  'plugins/*/api/db/migrate/*.rb'
].freeze

OptionParser.new do |opts|
  opts.banner = 'Usage: tools/check_migration_specs.rb [--cached | --base REF [--head REF]]'

  opts.on('--cached', 'Check staged migration additions') do
    options[:mode] = :cached
  end

  opts.on('--base REF', 'Check migrations added since REF') do |ref|
    options[:mode] = :base
    options[:base] = ref
  end

  opts.on('--head REF', 'Head ref for --base mode, defaults to HEAD') do |ref|
    options[:head] = ref
  end
end.parse!

def git(*)
  out, err, status = Open3.capture3('git', *)
  abort err unless status.success?

  out
end

def added_migrations(options)
  output =
    case options.fetch(:mode)
    when :cached
      git('diff', '--cached', '--name-status', '--diff-filter=A', '--', *MIGRATION_PATHS)
    when :base
      base = options.fetch(:base)
      head = options[:head] || 'HEAD'
      git('diff', '--name-status', '--diff-filter=A', "#{base}...#{head}", '--', *MIGRATION_PATHS)
    else
      raise "unsupported mode #{options[:mode].inspect}"
    end

  output.lines.filter_map do |line|
    status, path = line.split(/\s+/, 2)
    path&.strip if status == 'A'
  end
end

def expected_spec_path(migration_path)
  basename = File.basename(migration_path, '.rb')

  "api/spec/migrations/#{basename}_spec.rb"
end

def spec_available?(path, options)
  case options.fetch(:mode)
  when :cached
    system('git', 'cat-file', '-e', ":#{path}", out: File::NULL, err: File::NULL)
  when :base
    File.file?(path)
  else
    false
  end
end

missing = added_migrations(options).filter_map do |migration_path|
  spec_path = expected_spec_path(migration_path)
  [migration_path, spec_path] unless spec_available?(spec_path, options)
end

if missing.any?
  warn 'Missing migration specs:'
  missing.each do |migration_path, spec_path|
    warn "  #{migration_path} -> #{spec_path}"
  end
  exit 1
end

puts 'OK: added migrations have matching specs.'
