require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'

module Vpsadmin
  module Gems
    class Error < StandardError; end

    module_function

    PLAIN_PACKAGES = {
      api: 'api',
      client: 'client',
      console_router: 'console-router',
      download_mounter: 'download-mounter'
    }.freeze

    SOURCE_PACKAGES = {
      libnodectld: 'libnodectld',
      nodectl: 'nodectl',
      nodectld: 'nodectld'
    }.freeze

    SOURCE_CLOSURES = {
      'libnodectld' => %w[libnodectld libosctl osctl osctl-exportfs],
      'nodectl' => %w[nodectl libnodectld libosctl osctl osctl-exportfs],
      'nodectld' => %w[nodectld libnodectld libosctl osctl osctl-exportfs]
    }.freeze

    def root
      @root ||= File.realpath(File.join(__dir__, '..'))
    end

    def package_dir(name)
      File.join(root, 'packages', name)
    end

    def run!(*cmd, chdir: nil, env: {})
      opts = {}
      opts[:chdir] = chdir if chdir

      ok = system(env, *cmd, **opts)
      return if ok

      status = $?&.exitstatus || 1
      abort "#{cmd.shelljoin} failed with exit status #{status}"
    end

    def capture_json!(*cmd, chdir: nil, env: {})
      opts = {}
      opts[:chdir] = chdir if chdir

      out, err, status = Open3.capture3(env, *cmd, **opts)
      abort "#{cmd.shelljoin} failed with exit status #{status.exitstatus}: #{err}" unless status.success?

      JSON.parse(out)
    end

    def local_vpsadminos_path
      path = ENV.fetch('VPSADMINOS_PATH', '')
      return nil if path.empty?

      File.realpath(path)
    rescue Errno::ENOENT
      raise Error, "VPSADMINOS_PATH does not exist: #{path}"
    end

    def vpsadminos_flake_input_path
      out, err, status = Open3.capture3(
        'nix', 'flake', 'archive', '--json', root
      )

      unless status.success?
        detail = err.strip
        message = "Unable to resolve vpsadminos flake input from #{root}"
        message += ": #{detail}" unless detail.empty?

        raise Error, message
      end

      path = JSON.parse(out).dig('inputs', 'vpsadminos', 'path')

      if path.nil? || path.empty?
        raise Error,
              'nix flake archive did not return inputs.vpsadminos.path for ' \
              "#{root}"
      end

      File.realpath(path)
    rescue Errno::ENOENT
      raise Error,
            'Unable to run `nix flake archive`; install nix or set VPSADMINOS_PATH'
    rescue JSON::ParserError => e
      raise Error, "Unable to parse `nix flake archive` output: #{e.message}"
    end

    def vpsadminos_path
      @vpsadminos_path ||= local_vpsadminos_path || vpsadminos_flake_input_path
    end

    def export_vpsadminos_env!
      ENV['VPSADMINOS_PATH'] = vpsadminos_path
      ENV['VPSADMINOS_GEM_VERSION'] ||= "#{File.read(File.join(vpsadminos_path, '.version')).strip}.0"
    rescue Errno::ENOENT
      raise Error, "vpsAdminOS version not found in #{vpsadminos_path}"
    end

    def write_api_gemfile
      marker = '### vpsAdmin plugin marker ###'
      source = File.join(root, 'api', 'Gemfile')
      target = File.join(package_dir('api'), 'Gemfile')
      core = File.readlines(source).take_while { |line| line.strip != marker }.join

      File.write(target, core)

      Dir.glob(File.join(root, 'plugins', '*', 'api', 'Gemfile')).each do |file|
        plugin = File.basename(File.realpath(File.join(File.dirname(file), '..')))

        File.open(target, 'a') do |f|
          f.puts "# Plugin #{plugin}"
          f.write File.read(file)
        end
      end
    end

    def copy_source_gemfile(package, source)
      FileUtils.cp(
        File.join(root, source),
        File.join(package_dir(package), 'Gemfile')
      )
    end

    def format_gemset(dir)
      gemset = File.join(dir, 'gemset.nix')
      run!('nixfmt', gemset) if File.exist?(gemset)
    end

    def update_plain_package(task_name)
      package = PLAIN_PACKAGES.fetch(task_name)
      dir = package_dir(package)

      case task_name
      when :api
        write_api_gemfile
      when :console_router
        copy_source_gemfile(package, 'console_router/Gemfile')
      when :download_mounter
        copy_source_gemfile(package, 'download_mounter/Gemfile')
      end

      FileUtils.rm_f(File.join(dir, 'Gemfile.lock'))
      run!('bundix', '-l', chdir: dir, env: { 'TMPDIR' => '/tmp' })
      format_gemset(dir)
    end

    def source_paths
      {
        'libnodectld' => File.join(root, 'libnodectld'),
        'nodectl' => File.join(root, 'nodectl'),
        'nodectld' => File.join(root, 'nodectld'),
        'libosctl' => File.join(vpsadminos_path, 'libosctl'),
        'osctl' => File.join(vpsadminos_path, 'osctl'),
        'osctl-exportfs' => File.join(vpsadminos_path, 'osctl-exportfs')
      }
    end

    def gem_declarations(gemfile, source_gems)
      gemfile.lines.filter_map do |line|
        match = line.match(/^\s*gem ['"]([^'"]+)['"](?:,\s*['"]([^'"]+)['"])?/)
        next if match.nil?

        name = match[1]
        next unless source_gems.include?(name)

        [name, match[2]]
      end
    end

    def source_spec_lines(section)
      lines = section.lines
      spec_index = lines.index("  specs:\n")
      return [] if spec_index.nil?

      lines[(spec_index + 1)..] || []
    end

    def spec_blocks(lines)
      blocks = []
      current = nil

      lines.each do |line|
        if line.match?(/^    \S/)
          blocks << current if current
          current = [line]
        elsif current
          current << line
        end
      end

      blocks << current if current
      blocks
    end

    def normalize_dependencies(section, source_gems, canonical_deps)
      lines = section.lines
      kept = lines[1..].to_a.reject do |line|
        name = line[/^\s{2}([^ !(]+)/, 1]
        name && source_gems.include?(name)
      end

      source_lines = canonical_deps.map do |name, version|
        if version
          "  #{name} (= #{version})!\n"
        else
          "  #{name}!\n"
        end
      end

      ["DEPENDENCIES\n"] + (source_lines + kept).sort
    end

    def normalize_lockfile(path, source_gems, canonical_deps, bundled_with)
      sections = File.read(path).split(/\n(?=[A-Z][A-Z0-9 _-]*\n)/)
      source_specs = []
      kept_sections = []

      sections.each do |section|
        case section.lines.first&.strip
        when 'PATH'
          source_specs.concat(source_spec_lines(section))
        when 'GEM'
          lines = section.lines
          spec_index = lines.index("  specs:\n")
          abort 'Gemfile.lock has no GEM specs section' if spec_index.nil?

          prefix = lines[0..spec_index]
          blocks = spec_blocks(lines[(spec_index + 1)..].to_a + source_specs)
          sorted_specs = blocks.sort_by { |block| block.first[/^    ([^ (]+)/, 1] || '' }.flatten

          kept_sections << (prefix + sorted_specs).join
        when 'DEPENDENCIES'
          kept_sections << normalize_dependencies(section, source_gems, canonical_deps).join
        when 'BUNDLED WITH'
          kept_sections << if bundled_with
                             "BUNDLED WITH\n   #{bundled_with}\n"
                           else
                             section.sub(/\n+\z/, "\n")
                           end
        when 'CHECKSUMS'
          next
        else
          kept_sections << section.sub(/\n+\z/, "\n")
        end
      end

      normalized = kept_sections.map { |section| section.sub(/\n+\z/, '') }.join("\n\n")
      File.write(path, "#{normalized}\n")
    end

    def nix_expr_string(str)
      str.inspect
    end

    def nix_attr_name(str)
      if str.match?(/\A[A-Za-z_][A-Za-z0-9_'-]*\z/)
        str
      else
        nix_expr_string(str)
      end
    end

    def nix_value(value, indent = 0)
      pad = '  ' * indent
      child_pad = '  ' * (indent + 1)

      case value
      when Hash
        return '{ }' if value.empty?

        lines = ['{']
        value.keys.sort.each do |key|
          lines << "#{child_pad}#{nix_attr_name(key)} = #{nix_value(value.fetch(key), indent + 1)};"
        end
        lines << "#{pad}}"
        lines.join("\n")
      when Array
        return '[ ]' if value.empty?

        if value.all?(String)
          "[ #{value.map { |v| nix_expr_string(v) }.join(' ')} ]"
        else
          lines = ['[']
          value.each { |v| lines << "#{child_pad}#{nix_value(v, indent + 1)}" }
          lines << "#{pad}]"
          lines.join("\n")
        end
      when String
        nix_expr_string(value)
      when TrueClass
        'true'
      when FalseClass
        'false'
      when NilClass
        'null'
      else
        value.to_s
      end
    end

    def normalize_gemset(path, source_gems)
      data = capture_json!('nix', 'eval', '--json', '--file', path)

      source_gems.each do |name|
        next unless data.has_key?(name)

        data.fetch(name)['source'] = { 'type' => 'gem' }
      end

      File.write(path, "#{nix_value(data)}\n")
      run!('nixfmt', path)
    end

    def update_source_package(task_name)
      package = SOURCE_PACKAGES.fetch(task_name)
      dir = package_dir(package)
      paths = source_paths
      source_gems = paths.keys
      selected_sources = SOURCE_CLOSURES.fetch(package)

      Dir.chdir(dir) do
        original_gemfile = File.read('Gemfile')
        original_lockfile = File.exist?('Gemfile.lock') ? File.read('Gemfile.lock') : nil
        bundled_with = ENV['BUNDLED_WITH'] || original_lockfile&.match(/^BUNDLED WITH\n\s+(.+)\n/m)&.[](1)
        canonical_deps = gem_declarations(original_gemfile, source_gems)
        seen_sources = {}

        rewritten = original_gemfile.each_line.with_object(+'') do |line, ret|
          match = line.match(/^\s*gem ['"]([^'"]+)['"]/)

          if match && selected_sources.include?(match[1])
            name = match[1]
            seen_sources[name] = true
            ret << "gem #{name.inspect}, path: #{paths.fetch(name).inspect}\n"
          else
            ret << line
          end
        end

        (selected_sources - seen_sources.keys).each do |name|
          rewritten << "\n" unless rewritten.end_with?("\n")
          rewritten << "gem #{name.inspect}, path: #{paths.fetch(name).inspect}\n"
        end

        FileUtils.rm_f(%w[Gemfile.lock gemset.nix])
        File.write('Gemfile', rewritten)

        begin
          run!('bundle', 'lock', '--add-platform', 'ruby', '--add-platform', 'x86_64-linux')
          run!('bundix', '-l')
        ensure
          File.write('Gemfile', original_gemfile)
        end

        normalize_lockfile('Gemfile.lock', source_gems, canonical_deps, bundled_with)
        normalize_gemset('gemset.nix', source_gems)
      end
    end
  end
end

namespace :vpsadmin do
  gem_tasks = {
    api: [],
    client: [],
    console_router: [],
    download_mounter: [],
    libnodectld: [],
    nodectl: [:libnodectld],
    nodectld: [:libnodectld]
  }

  desc 'Refresh all packaged gem dependencies'
  task gems: gem_tasks.keys.map { |gem| "gems:#{gem}" }

  namespace :gems do
    task :environment do
      Vpsadmin::Gems.export_vpsadminos_env!
    rescue Vpsadmin::Gems::Error => e
      abort e.message
    end

    Vpsadmin::Gems::PLAIN_PACKAGES.each_key do |gem|
      desc "Refresh #{gem} package metadata"
      task gem do
        Vpsadmin::Gems.update_plain_package(gem)
      end
    end

    Vpsadmin::Gems::SOURCE_PACKAGES.each_key do |gem|
      desc "Refresh #{gem} package metadata"
      task gem => [:environment] + gem_tasks.fetch(gem).map { |dep| "gems:#{dep}" } do
        Vpsadmin::Gems.update_source_package(gem)
      end
    end
  end
end
