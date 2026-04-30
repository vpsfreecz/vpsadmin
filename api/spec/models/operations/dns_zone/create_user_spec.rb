# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::CreateUser do
  let(:chain) { instance_double(TransactionChain) }

  def attrs(name)
    {
      name: name,
      zone_source: :internal_source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: 'dns@example.test'
    }
  end

  before do
    allow(TransactionChains::DnsZone::CreateUser).to receive(:fire2) do |args:, kwargs:|
      [chain, args.first, kwargs]
    end
  end

  it 'assigns non-admin zones to the current user automatically' do
    with_current_context(user: SpecSeed.user) do
      ret_chain, zone = described_class.run(attrs("user-#{SecureRandom.hex(3)}.example.test."))

      expect(ret_chain).to eq(chain)
      expect(zone.user).to eq(SpecSeed.user)
      expect(zone).to be_forward_role
    end
  end

  it 'derives reverse zone role from reverse suffixes' do
    with_current_context(user: SpecSeed.user) do
      _chain, zone = described_class.run(attrs("#{SecureRandom.hex(3)}.2.0.192.in-addr.arpa."))

      expect(zone).to be_reverse_role
    end
  end

  it 'rejects cross-user subdomain collisions for non-admin users' do
    create_dns_zone!(name: "taken-#{SecureRandom.hex(3)}.example.test.", user: SpecSeed.other_user)

    existing = DnsZone.last

    with_current_context(user: SpecSeed.user) do
      expect do
        described_class.run(attrs("sub.#{existing.name}"))
      end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /already taken/)
    end
  end

  it 'allows admins to bypass user collision checks' do
    existing = create_dns_zone!(name: "admin-taken-#{SecureRandom.hex(3)}.example.test.", user: SpecSeed.other_user)

    with_current_context(user: SpecSeed.admin) do
      _chain, zone = described_class.run(attrs("sub.#{existing.name}").merge(user: SpecSeed.user))

      expect(zone.user).to eq(SpecSeed.user)
    end
  end

  it 'passes seed_vps through to the user-zone transaction chain' do
    with_current_context(user: SpecSeed.user) do
      described_class.run(attrs("seed-#{SecureRandom.hex(3)}.example.test.").merge(seed_vps: true))
    end

    expect(TransactionChains::DnsZone::CreateUser).to have_received(:fire2) do |args:, kwargs:|
      expect(args.first).to be_a(DnsZone)
      expect(kwargs).to eq(seed_vps: true)
    end
  end
end
