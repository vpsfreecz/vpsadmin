require 'spec_helper'

RSpec.describe IpAddress do
  around { |example| with_current_context { example.run } }

  it 'records the environment whose quota was charged on direct registration' do
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4
    ip = create_ip_address!(user: SpecSeed.user)

    expect(ip.charged_environment).to eq(SpecSeed.environment)
    expect(config.reload.ipv4).to eq(before + ip.size)
  end

  it 'records the explicit charge environment for a batch without an address location' do
    network = SpecSeed.network_v4.dup
    network.update!(address: '198.51.100.0')
    LocationNetwork.create!(network: network, location: SpecSeed.location, autopick: true, userpick: true)
    config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4

    ips = network.add_ips(2, user: SpecSeed.user, environment: SpecSeed.environment)
    expect(ips.map(&:charged_environment)).to all(eq(SpecSeed.environment))
    expect(config.reload.ipv4).to eq(before + ips.sum(&:size))
  end

  it 'rejects direct owned registration without an environment before creating addresses' do
    before = described_class.count
    expect do
      described_class.register(IPAddress.parse('192.0.2.250'), network: SpecSeed.network_v4,
                                                               user: SpecSeed.user, prefix: 32, size: 1)
    end.to raise_error(ArgumentError, /charge environment/)
    expect(described_class.count).to eq(before)
  end
end
