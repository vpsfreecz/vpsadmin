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

  [nil, true, false].each do |compressed|
    it "loads #{compressed.inspect} compressed-send policy with missing meaning true" do
      config = { vpsadmin: { node_name: 'test-node' } }
      config[:zfs] = { send: { compressed: compressed } } unless compressed.nil?
      allow(File).to receive(:read).with(cfg.file).and_return(config.to_yaml)
      allow(Dir).to receive(:glob).and_return([])

      expect(cfg.load(false)).to be(true)
      expect(cfg.get(:zfs, :send, :compressed)).to be(compressed.nil? ? true : compressed)
    end
  end

  [nil, 'false', 0, [], {}].each do |compressed|
    it "rejects #{compressed.inspect} as a compressed-send setting" do
      yaml = { zfs: { send: { compressed: compressed } } }.to_yaml

      expect { cfg.load_yaml(yaml) }.to raise_error(ArgumentError, 'zfs.send.compressed must be a boolean')
    end
  end

  it 'accepts a boolean runtime patch' do
    cfg.patch('zfs' => { 'send' => { 'compressed' => false } })

    expect(cfg.get(:zfs, :send, :compressed)).to be(false)
  end

  it 'rejects a string runtime patch without changing the selected policy' do
    expect { cfg.patch('zfs' => { 'send' => { 'compressed' => 'false' } }) }
      .to raise_error(ArgumentError, 'zfs.send.compressed must be a boolean')
    expect(cfg.get(:zfs, :send, :compressed)).to be(true)
  end

  it 'reports an invalid YAML setting instead of loading it' do
    allow(File).to receive(:read).with(cfg.file).and_return('zfs: {send: {compressed: "false"}}')

    expect { expect(cfg.load(false)).to be(false) }
      .to output(/zfs.send.compressed must be a boolean/).to_stderr
    expect(cfg.get(:zfs, :send, :compressed)).to be(true)
  end

  ['zfs: false', 'zfs: {send: false}'].each do |yaml|
    it "rejects malformed policy mappings in #{yaml}" do
      expect { cfg.load_yaml(yaml) }.to raise_error(ArgumentError, /must be a mapping/)
    end
  end

  it 'preserves the active policy and skips callbacks when a secret reload is rejected' do
    secret_file = '/test/nodectld-secret.yml'
    cfg.patch(zfs: { send: { compressed: false } })
    previous = Marshal.load(Marshal.dump(cfg.get))
    callback = instance_spy(Proc)
    cfg.on_update(:spec) { callback.call }
    allow(File).to receive(:read).with(cfg.file).and_return('vpsadmin: {node_name: test-node}')
    allow(Dir).to receive(:glob).and_return([secret_file], [])
    allow(File).to receive(:read).with(secret_file).and_return('zfs: {send: {compressed: "false"}}')
    allow(cfg).to receive(:load_db_settings)

    expect { expect(cfg.reload).to be(false) }
      .to output(/zfs.send.compressed must be a boolean/).to_stderr
    expect(cfg.get(:zfs, :send, :compressed)).to be(false)
    expect(cfg.get).to eq(previous)
    expect(callback).not_to have_received(:call)
    expect(cfg).not_to have_received(:load_db_settings)

    allow(Dir).to receive(:glob).and_return([secret_file], [])
    allow(File).to receive(:read).with(secret_file).and_return('zfs: {send: {compressed: true}}')

    expect(cfg.reload).to be(true)
    expect(cfg.get(:zfs, :send, :compressed)).to be(true)
    expect(callback).to have_received(:call).once
    expect(cfg).to have_received(:load_db_settings).once
  end
end
