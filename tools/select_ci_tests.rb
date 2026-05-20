#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'yaml'

class CiTestSelector
  class Selection
    attr_reader :mode, :filter, :tags, :reason

    def initialize(mode:, filter:, tags:, reason:)
      @mode = mode
      @filter = filter
      @tags = tags
      @reason = reason
    end
  end

  SAFE_TAG = /\A[A-Za-z0-9_.-]+\z/
  FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

  def self.default_config_path
    File.expand_path('../tests/ci-selection.yml', __dir__)
  end

  def initialize(config_path: self.class.default_config_path)
    @config_path = config_path
    @config = YAML.safe_load_file(config_path)
    @skip_patterns = Array(@config.fetch('skip', []))
    @full_patterns = Array(@config.fetch('full', []))
    @select_rules = Array(@config.fetch('select', []))
  end

  def select(paths)
    tags = Set.new
    matched = []
    skipped = []
    unmapped = []

    normalize_paths(paths).each do |path|
      if match_any?(@skip_patterns, path)
        skipped << path
        next
      end

      if match_any?(@full_patterns, path)
        return full("full rule matched #{path}")
      end

      path_tags = tags_for_path(path)

      if path_tags.empty?
        unmapped << path
      else
        path_tags.each { |tag| tags.add(tag) }
        matched << [path, path_tags]
      end
    end

    if matched.empty? && unmapped.empty?
      reason = skipped.empty? ? 'no changed files' : "only skipped files changed: #{summarize_paths(skipped)}"
      return skip(reason)
    end

    return full("unmapped runtime paths: #{summarize_paths(unmapped)}") if unmapped.any?

    selected(tags.to_a.sort, "matched #{matched.length} runtime path(s)")
  end

  def self.write_github_output(path, selection)
    File.open(path, 'a') do |f|
      {
        'mode' => selection.mode,
        'filter' => selection.filter.to_s,
        'reason' => selection.reason.to_s,
        'tags' => selection.tags.join(',')
      }.each do |key, value|
        f.puts("#{key}=#{value}")
      end
    end
  end

  protected

  attr_reader :config

  def normalize_paths(paths)
    paths.map { |path| path.to_s.strip.sub(%r{\A\./}, '') }.reject(&:empty?).uniq
  end

  def tags_for_path(path)
    tags = @select_rules.each_with_object(Set.new) do |rule, ret|
      next unless match_any?(Array(rule.fetch('paths')), path)

      Array(rule.fetch('tags')).each do |tag|
        validate_tag!(tag)
        ret.add(tag)
      end
    end

    tags.to_a
  end

  def validate_tag!(tag)
    return if SAFE_TAG.match?(tag)

    raise ArgumentError, "invalid tag #{tag.inspect} in #{@config_path}"
  end

  def selected(tags, reason)
    Selection.new(
      mode: 'selected',
      filter: "tag=ci && (#{tags.map { |tag| "tag=#{tag}" }.join(' || ')})",
      tags:,
      reason:
    )
  end

  def full(reason)
    Selection.new(mode: 'full', filter: 'tag=ci', tags: [], reason:)
  end

  def skip(reason)
    Selection.new(mode: 'skip', filter: '', tags: [], reason:)
  end

  def match_any?(patterns, path)
    patterns.any? { |pattern| match_pattern?(pattern, path) }
  end

  def match_pattern?(pattern, path)
    pattern = pattern.to_s
    return true if File.fnmatch?(pattern, path, FNMATCH_FLAGS)

    if pattern.end_with?('/**')
      prefix = pattern.delete_suffix('/**')
      return path == prefix || path.start_with?("#{prefix}/")
    end

    false
  end

  def summarize_paths(paths)
    shown = paths.first(5)
    suffix = paths.length > shown.length ? " and #{paths.length - shown.length} more" : ''
    "#{shown.join(', ')}#{suffix}"
  end
end

if $0 == __FILE__
  options = {
    config_path: CiTestSelector.default_config_path,
    changed_files: nil,
    github_output: ENV.fetch('GITHUB_OUTPUT', nil)
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: select_ci_tests.rb [options]'

    opts.on('--config PATH', 'Path to tests/ci-selection.yml') do |path|
      options[:config_path] = path
    end

    opts.on('--changed-files PATH', 'File with one changed path per line') do |path|
      options[:changed_files] = path
    end

    opts.on('--github-output PATH', 'Append GitHub Actions outputs to PATH') do |path|
      options[:github_output] = path
    end
  end.parse!

  paths =
    if options[:changed_files]
      File.readlines(options[:changed_files], chomp: true)
    else
      $stdin.each_line(chomp: true).to_a
    end

  selection = CiTestSelector.new(config_path: options[:config_path]).select(paths)

  puts "mode=#{selection.mode}"
  puts "filter=#{selection.filter}"
  puts "reason=#{selection.reason}"
  puts "tags=#{selection.tags.join(',')}" if selection.tags.any?

  CiTestSelector.write_github_output(options[:github_output], selection) if options[:github_output]
end
