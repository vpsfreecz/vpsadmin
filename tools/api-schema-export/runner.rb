# frozen_string_literal: true

require 'fileutils'
require 'open3'
require_relative 'bootstrap'
require_relative 'snapshot'

module VpsAdmin
  module SchemaExport
    class Runner
      FIXTURE_INPUTS = %w[
        api/db/schema.rb api/spec/support/db_setup.rb api/spec/support/spec_seed.rb
        api/spec/support/spec_plugins.rb api/config/dataset_plans.rb
        api/config/dataset_properties.rb tools/test_db.rb
      ].freeze

      def initialize(root:, output:, api_version:)
        @root = root
        @output = File.expand_path(output)
        @api_version = api_version
      end

      def run
        raise UnsafeInput, 'Export requires a clean committed source checkout' unless git('status', '--porcelain').empty?
        raise UnsafeInput, 'Schema export requires HaveAPI 0.32.0' unless Gem.loaded_specs.fetch('haveapi').version.to_s == '0.32.0'
        raise UnsafeInput, 'Refusing an existing export destination' if File.exist?(@output) || File.symlink?(@output)

        api = Bootstrap.new(root: @root).load
        api.activate_locale(:en)
        description = api.describe_version(HaveAPI::Context.new(api, version: @api_version, user: nil, doc: true))
        snapshot = Snapshot.build(description:, api_version: @api_version, protocol_version: HaveAPI::PROTOCOL_VERSION)
        inventory = Snapshot.inventory(snapshot.fetch('description'))
        bytes = Snapshot.canonical(snapshot)
        provenance = provenance(inventory, Digest::SHA256.hexdigest(bytes))
        FileUtils.mkdir_p(@output)
        File.write(File.join(@output, 'schema.json'), bytes)
        File.write(File.join(@output, 'provenance.json'), Snapshot.canonical(provenance))
        FileUtils.cp(File.join(__dir__, 'Gemfile.lock'), File.join(@output, 'tooling.Gemfile.lock'))
        puts "Exported #{inventory.fetch('actions')} actions from #{inventory.fetch('resources')} resources"
      end

      private

      def provenance(inventory, schema_digest)
        {
          'acquisition' => 'mounted-source',
          'source' => { 'repository' => 'git@github.com:vpsfreecz/vpsadmin.git', 'revision' => git('rev-parse', 'HEAD').strip },
          'api_version' => @api_version,
          'protocol_version' => HaveAPI::PROTOCOL_VERSION,
          'profile' => 'vpsadmin-full-fixture',
          'locale' => 'en',
          'schema_sha256' => schema_digest,
          'inventory' => inventory,
          'inputs' => FIXTURE_INPUTS.to_h { |path| [path, file_digest(path)] },
          'tooling' => {
            'ruby' => RUBY_VERSION,
            'bundler' => Bundler::VERSION,
            'gemfile_sha256' => file_digest('tools/api-schema-export/Gemfile'),
            'lock_sha256' => file_digest('tools/api-schema-export/Gemfile.lock'),
            'gems' => gem_inventory
          },
          'database' => { 'engine' => 'MariaDB', 'version' => ActiveRecord::Base.connection.select_value('SELECT VERSION()') },
          'plugins' => plugin_inventory
        }
      end

      def gem_inventory
        Gem.loaded_specs.sort.to_h do |name, spec|
          gem_file = File.join(spec.base_dir, 'cache', "#{spec.full_name}.gem")
          [name, { 'version' => spec.version.to_s, 'gem_sha256' => File.file?(gem_file) ? Digest::SHA256.file(gem_file).hexdigest : nil }]
        end
      end

      def plugin_inventory
        migrations = ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations')
        VpsAdmin::API::Plugin.registered.sort.to_h do |id, plugin|
          relative = "plugins/#{id}"
          files = git('ls-files', '-z', '--', relative).split("\0")
          hashes = files.to_h { |path| [path, file_digest(path)] }
          [id.to_s, {
            'version' => plugin.version,
            'source_sha256' => Digest::SHA256.hexdigest(Snapshot.canonical(hashes)),
            'migration_versions' => migrations.filter_map do |value|
              match = value.match(/\A(\d+)-#{Regexp.escape(id.to_s)}\z/)
              match[1].to_i if match
            end.sort
          }]
        end
      end

      def file_digest(relative)
        Digest::SHA256.file(File.join(@root, relative)).hexdigest
      end

      def git(*)
        stdout, stderr, status = Open3.capture3('git', '-C', @root, *)
        raise UnsafeInput, "Source identity query failed: #{stderr.lines.first}" unless status.success?

        stdout
      end
    end
  end
end
