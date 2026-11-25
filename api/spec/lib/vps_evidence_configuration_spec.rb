require 'spec_helper'
require 'tmpdir'

RSpec.describe VpsEvidence::Configuration do
  around do |example|
    saved = %i[@configured @finalized @site_defaults].to_h { |key| [key, VpsEvidence.instance_variable_get(key)] }
    VpsEvidence.instance_variable_set(:@configured, false)
    VpsEvidence.instance_variable_set(:@finalized, false)
    VpsEvidence.instance_variable_set(:@site_defaults, {}.freeze)
    example.run
  ensure
    saved.each { |key, value| VpsEvidence.instance_variable_set(key, value) }
  end

  it 'uses the actual trusted loader before registration with built-in, site and nonnull runtime precedence' do
    Dir.mktmpdir('vps-evidence-config') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'vps_evidence.rb'), <<~RUBY)
        VpsEvidence.configure do
          signal :rtnl_latency, window_seconds: 900, threshold_seconds: 10, repeat_seconds: 600, freshness_seconds: 30
        end
      RUBY
      allow(VpsAdmin::API).to receive(:root).and_return(root)
      VpsAdmin::API.load_configurable(:vps_evidence)
      VpsEvidence.finalize!
      expect(VpsEvidence.config('rtnl_latency', {})).to include(enabled: false, window_seconds: 900, threshold_seconds: 10, repeat_seconds: 600)
      expect(VpsEvidence.config('rtnl_latency', window_seconds: 1200, threshold_seconds: nil)).to include(window_seconds: 1200, threshold_seconds: 10)
      expect { VpsEvidence.configure }.to raise_error(ArgumentError, /initialized/)
    end
  end

  it 'rejects unknown signals, keys, duplicate declarations and invalid combinations' do
    expect { described_class.new.signal(:unknown) }.to raise_error(VpsEvidence::InvalidEvent)
    expect { described_class.new.signal(:rtnl_latency, enabled: true) }.to raise_error(ArgumentError)
    expect { described_class.new.signal(:rtnl_latency, window_seconds: 60, threshold_seconds: 61) }.to raise_error(ArgumentError)
    config = described_class.new
    config.signal(:rtnl_latency)
    expect { config.signal(:rtnl_latency) }.to raise_error(ArgumentError, /Duplicate/)
  end

  it 'preserves stored overrides, clears empty numeric overrides and audits the actual value change' do
    VpsEvidence.configure { signal :rtnl_latency, threshold_seconds: 10 }
    row = SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'threshold_seconds')
    row.update!(value: 20)
    SysConfig.register('vps_evidence_rtnl_latency', :threshold_seconds, Integer, default: nil)
    expect(row.reload.value).to eq(20)
    row.set_value('')
    PaperTrail.request(enabled: true) { row.save! }
    expect(row.reload.value).to be_nil
    expect(VpsEvidence.config('rtnl_latency')[:threshold_seconds]).to eq(10)
    expect(row.versions.last.event).to eq('update')
    expect(VpsEvidence.config('rtnl_latency')[:enabled]).to be(false)
  end
end
