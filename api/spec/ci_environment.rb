# frozen_string_literal: true

require 'bundler'
require 'json'
require 'digest'
require 'yaml'
require 'tempfile'
require 'rspec/core/version'

module SpecCiEnvironment
  API_ROOT = File.expand_path('..', __dir__).freeze
  WORKFLOW = File.expand_path('../../.github/workflows/api-specs.yml', __dir__).freeze
  MAX_LOCK_BYTES = 1024 * 1024
  MAX_JSON_BYTES = 1024 * 1024
  MAX_SPECS = 1024
  class Invalid < StandardError; end

  module_function

  def capture(mode:, topic:, api_root: API_ROOT)
    raise Invalid unless %w[full core].include?(mode) && topics.include?(topic)

    root = File.realpath(api_root)
    lock = File.join(root, 'Gemfile.lock')
    raise Invalid unless File.expand_path(Bundler.default_lockfile.to_s) == lock

    bytes = File.open(lock, File::RDONLY | File::NOFOLLOW) do |file|
      raise Invalid unless file.stat.file? && file.size.between?(1, MAX_LOCK_BYTES)

      file.read(MAX_LOCK_BYTES + 1)
    end
    raise Invalid unless bytes.bytesize <= MAX_LOCK_BYTES

    validate_lock!(bytes)
    specs = Bundler.load.specs.to_a
    raise Invalid if specs.length > MAX_SPECS

    resolved = specs.map do |spec|
      {
        name: safe_value(spec.name, /\A[A-Za-z0-9_.-]+\z/),
        version: safe_value(spec.version.to_s, /\A[A-Za-z0-9_.-]+\z/),
        platform: safe_value(spec.platform.to_s, /\A[A-Za-z0-9_.-]+\z/)
      }
    end.sort_by { |spec| spec.values_at(:name, :version, :platform) }
    evidence = {
      mode: mode,
      topic: topic,
      ruby: safe_value(RUBY_DESCRIPTION, /\A[\x20-\x7e]+\z/, 512),
      bundler: safe_value(Bundler::VERSION, /\A[0-9A-Za-z_.-]+\z/),
      rspec: safe_value(RSpec::Core::Version::STRING, /\A[0-9A-Za-z_.-]+\z/),
      gemfile_lock_sha256: Digest::SHA256.hexdigest(bytes),
      rubygems: safe_value(Gem::VERSION, /\A[0-9A-Za-z_.-]+\z/),
      resolved_specs: resolved
    }
    json = "#{JSON.pretty_generate(evidence)}\n"
    raise Invalid if json.bytesize > MAX_JSON_BYTES

    directory = File.join(root, 'tmp')
    raise Invalid unless File.lstat(directory).directory? && File.realpath(directory) == directory

    lock_output = File.join(directory, "rspec-Gemfile-#{mode}-#{topic}.lock")
    json_output = File.join(directory, "rspec-environment-#{mode}-#{topic}.json")
    [lock_output, json_output].each do |path|
      raise Invalid if File.exist?(path) || File.symlink?(path)
    end
    publish(directory, lock_output, bytes)
    publish(directory, json_output, json)
    evidence
  rescue StandardError
    # Never include parser, filesystem or source excerpts in CI diagnostics.
    raise Invalid, 'RSpec environment evidence unavailable', cause: nil
  end

  def topics
    workflow = YAML.load_file(WORKFLOW, aliases: true)
    jobs = workflow.fetch('jobs')
    full = jobs.fetch('api-specs-full').fetch('strategy').fetch('matrix').fetch('include')
    core = jobs.fetch('api-specs-core').fetch('strategy').fetch('matrix').fetch('include')
    names = full.map { |entry| entry.fetch('topic') }
    raise Invalid unless names == core.map { |entry| entry.fetch('topic') }
    raise Invalid unless names.any? && names.uniq == names &&
                         names.all? { |name| name.is_a?(String) && /\A[a-z][a-z-]{0,63}\z/.match?(name) }

    names
  end

  def validate_lock!(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    raise Invalid unless text.valid_encoding? && !text.include?("\0")

    sections = text.lines.reject { |line| line.strip.empty? || /\A\s/.match?(line) }.map(&:chomp)
    allowed = Bundler::LockfileParser::KNOWN_SECTIONS - ['GIT', 'PATH', 'PLUGIN SOURCE']
    raise Invalid unless sections.include?('GEM') && sections.all? { |section| allowed.include?(section) }

    # Validate source options before Bundler can diagnose an unsafe URI.
    source_options = false
    text.each_line do |line|
      line = line.chomp
      if line == 'GEM'
        source_options = true
      elsif source_options && line == '  specs:'
        source_options = false
      elsif source_options && !line.empty?
        raise Invalid unless ['  remote: https://rubygems.org', '  remote: https://rubygems.org/'].include?(line)
      end
    end
    raise Invalid if source_options

    parsed = Bundler::LockfileParser.new(text)
    raise Invalid unless parsed.sources.any?

    parsed.sources.each do |source|
      raise Invalid unless source.instance_of?(Bundler::Source::Rubygems)

      safe = source.remotes.any? && source.remotes.all? do |remote|
        %w[https://rubygems.org https://rubygems.org/].include?(remote.to_s)
      end
      raise Invalid unless safe
    end
  end

  def safe_value(value, pattern, max = 192)
    raise Invalid unless value.is_a?(String) && value.bytesize <= max && pattern.match?(value)

    value
  end

  def publish(directory, output, bytes)
    Tempfile.create(['rspec-evidence-', '.tmp'], directory) do |temporary|
      temporary.binmode
      temporary.write(bytes)
      temporary.flush
      # A hard link publishes a complete file without replacing an existing one.
      File.link(temporary.path, output)
    end
  end
end

if $0 == __FILE__
  begin
    SpecCiEnvironment.capture(mode: ENV.fetch('SPEC_MODE'), topic: ENV.fetch('TOPIC'))
  rescue StandardError
    warn 'ERROR: RSpec environment evidence unavailable'
    exit 1
  end
end
