# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../../lib/vpsadmin/api/i18n/catalog'

RSpec.describe VpsAdmin::API::I18n::Catalog do
  it 'discovers literal labels in plugin root metadata through the normal source scanner' do
    Dir.mktmpdir('sysconfig-label-catalog-') do |root|
      path = File.join(root, 'plugins', 'example', 'meta.rb')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        VpsAdmin::API::Plugin.register(:example) do
          config do
            SysConfig.register :plugin_example, :setting, String,
              label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_example.setting', default: 'Example setting')
          end
        end
      RUBY
      catalog = described_class.new(root:)
      expect(catalog.send(:source_keys)).to include('sysconfig.labels.plugin_example.setting')
    end
  end
end
