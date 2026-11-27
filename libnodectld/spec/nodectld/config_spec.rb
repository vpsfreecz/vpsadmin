# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/config'
require 'nodectld/export_mounts'
require 'nodectld/vps_os_release'

RSpec.describe NodeCtld::AppConfig do
  let(:cfg) { described_class.new('/tmp/nodectld-config-spec.yml') }

  before do
    cfg.instance_variable_set(:@cfg, Marshal.load(Marshal.dump(NodeCtld::IMPLICIT_CONFIG)))
  end

  it 'symbolizes nested keys when patching runtime config' do
    cfg.patch(
      'mbuffer' => {
        'send' => {
          'command' => '/run/test/faulty-mbuffer'
        }
      }
    )

    expect(cfg.get(:mbuffer, :send, :command)).to eq('/run/test/faulty-mbuffer')
  end

  describe 'runtime modes' do
    let(:config_dir) { Dir.mktmpdir('nodectld-config-') }
    let(:cfg) { described_class.new(File.join(config_dir, 'nodectld.yml')) }

    after { FileUtils.remove_entry(config_dir) }

    before do
      stub_const('NodeCtld::SECRET_CONFIGS', [])
      allow(cfg).to receive(:load_db_settings)
    end

    def write_config(mode, enabled: true)
      File.write(cfg.file, YAML.dump({
                                     'mode' => mode,
                                     'export_mounts' => { 'enable' => enabled },
                                     'vps_os_release' => { 'enable' => enabled }
                                   }))
    end

    it 'disables host-container services in minimal mode, including after reload' do
      write_config('minimal')
      expect(cfg.load(false)).to be(true)
      expect(cfg.get(:export_mounts, :enable)).to be(false)
      expect(cfg.get(:vps_os_release, :enable)).to be(false)

      cfg.patch(export_mounts: { enable: true }, vps_os_release: { enable: true })
      cfg.reload

      expect(cfg.get(:export_mounts, :enable)).to be(false)
      expect(cfg.get(:vps_os_release, :enable)).to be(false)
    end

    it 'preserves enabled and disabled services in standard mode' do
      [true, false].each do |enabled|
        write_config('standard', enabled:)
        expect(cfg.load(false)).to be(true)
        expect(cfg.get(:export_mounts, :enable)).to be(enabled)
        expect(cfg.get(:vps_os_release, :enable)).to be(enabled)
      end
    end

    it 'enables both services by default in standard mode' do
      File.write(cfg.file, YAML.dump('mode' => 'standard'))
      cfg.load(false)

      expect(cfg.get(:export_mounts, :enable)).to be(true)
      expect(cfg.get(:vps_os_release, :enable)).to be(true)
    end

    [NodeCtld::ExportMounts, NodeCtld::VpsOsRelease].each do |service_class|
      it "does not start or refresh #{service_class} in minimal mode" do
        write_config('minimal')
        cfg.load(false)
        $CFG = cfg
        service = service_class.send(:allocate)

        allow(NodeCtld::NodeBunny).to receive(:create_channel)
        allow(service).to receive(:osctl_parse)
        service.send(:initialize)
        service.update_ct(Object.new)
        service.update_vps_ids([123])
        service.update_all_vps

        expect(NodeCtld::NodeBunny).not_to have_received(:create_channel)
        expect(service).not_to have_received(:osctl_parse)
      end
    end
  end
end
