# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'open3'
require_relative 'safety'

RSpec.describe VpsAdmin::SchemaExport::Safety do
  let(:root) { Dir.mktmpdir('vpsadmin-schema-safety-') }

  around do |example|
    FileUtils.mkdir_p(File.join(root, 'api/config'))
    example.run
  ensure
    FileUtils.remove_entry(root)
  end

  def safety(env = {})
    described_class.new(root:, env:)
  end

  def clean_child_environment
    ENV.keys.grep(/\A(?:BUNDLE|BUNDLER|RUBY)/).to_h { |name| [name, nil] }
  end

  it 'accepts only the controlled configuration files without loading the API' do
    %w[dataset_plans.rb dataset_properties.rb].each do |name|
      File.write(File.join(root, 'api/config', name), 'raise "must not execute"')
    end

    expect { safety.check! }.not_to raise_error
    expect(defined?(ActiveRecord)).to be_nil
  end

  it 'rejects inherited connection settings even when empty and does not print values' do
    %w[DATABASE_URL VPSADMIN_PLUGIN_DIR VPSADMIN_TEST_DB_NAME VPSADMIN_TEST_DB_PORT
       VPSADMIN_TEST_DB_STATE_DIR VPSADMIN_TEST_DB_AUTO BUNDLE_GEMFILE BUNDLE_PATH
       BUNDLE_BIN_PATH MYSQL_PWD MARIADB_HOST].each do |name|
      ['', 'private-connection-value'].each do |value|
        expect { safety(name => value).check! }
          .to raise_error(VpsAdmin::SchemaExport::UnsafeInput, "Refusing inherited #{name}")
      end
    end
  end

  it 'rejects a non-test Rack environment before loading configuration' do
    expect { safety('RACK_ENV' => 'production').check! }
      .to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /RACK_ENV=test/)
    expect { safety('RACK_ENV' => 'test').check! }.not_to raise_error
  end

  it 'rejects database and executable local overrides without evaluating them' do
    %w[database.yml api.rb hooks.rb incident_reports.rb].each do |name|
      path = File.join(root, 'api/config', name)
      File.write(path, 'raise "must not execute"')
      expect { safety.check! }
        .to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /uncontrolled API configuration/)
      File.unlink(path)
    end
  end

  it 'rejects symlinks even when their target would otherwise be allowed' do
    path = File.join(root, 'api/config/dataset_plans.rb')
    File.symlink(File::NULL, path)
    expect { safety.check! }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /symlinks/)
  end

  it 'rejects a symlinked configuration directory' do
    config = File.join(root, 'api/config')
    FileUtils.rm_r(config)
    File.symlink(root, config)
    expect { safety.check! }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /symlinked/)
  end

  it 'rejects local plugin and Bundler directories and non-full plugin profiles' do
    FileUtils.mkdir_p(File.join(root, 'api/plugins'))
    expect { safety.check! }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /local override/)
    FileUtils.rm_r(File.join(root, 'api/plugins'))
    expect { safety('VPSADMIN_PLUGINS' => 'none').check! }
      .to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /all-plugin/)
  end

  it 'rejects inherited database settings at the executable boundary before loading Bundler' do
    tool = File.expand_path('../export-api-schema', __dir__)
    env = clean_child_environment
    env['DATABASE_URL'] = 'private-connection-value'
    stdout, stderr, status = Open3.capture3(env, '/bin/sh', tool, '--output', File.join(root, 'unused'))
    expect(status.exitstatus).to eq(1)
    expect(stdout).to be_empty
    expect(stderr).to eq("Refusing inherited DATABASE_URL\n")
    expect(File).not_to exist(File.join(root, 'unused'))
  end

  it 'refuses Ruby preloads before Ruby starts and ignores inherited Ruby search paths' do
    tool = File.expand_path('../export-api-schema', __dir__)
    preload = File.join(root, 'preload.rb')
    marker = File.join(root, 'executed')
    File.write(preload, "File.write(#{marker.inspect}, 'executed')")
    _, stderr, status = Open3.capture3(clean_child_environment.merge('RUBYOPT' => "-r#{preload}"),
                                       '/bin/sh', tool, '--help')
    expect(status.exitstatus).to eq(1)
    expect(stderr).to eq("Refusing inherited RUBYOPT\n")
    expect(File).not_to exist(marker)

    File.write(File.join(root, 'optparse.rb'), "File.write(#{marker.inspect}, 'executed')")
    stdout, _, status = Open3.capture3(clean_child_environment.merge('RUBYLIB' => root), '/bin/sh', tool, '--help')
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include('Usage: tools/export-api-schema')
    expect(File).not_to exist(marker)
  end
end
