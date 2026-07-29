# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChain do
  let(:resource_fact_chains) do
    [
      TransactionChains::DnsResolver::Destroy,
      TransactionChains::DnsResolver::Update,
      TransactionChains::DnsZone::CreateRecord,
      TransactionChains::DnsZone::CreateUser,
      TransactionChains::DnsZone::DestroyRecord,
      TransactionChains::DnsZone::DestroyUser,
      TransactionChains::DnsZone::SetReverseRecord,
      TransactionChains::DnsZone::UnsetReverseRecord,
      TransactionChains::DnsZone::Update,
      TransactionChains::DnsZone::UpdateRecord,
      TransactionChains::DnsZoneTransfer::Create,
      TransactionChains::DnsZoneTransfer::Destroy,
      TransactionChains::Export::Update,
      TransactionChains::HostIpAddress::Destroy,
      TransactionChains::Ip::Update,
      TransactionChains::Lifetimes::Wrapper,
      TransactionChains::NetworkInterface::Update,
      TransactionChains::Vps::Update
    ]
  end

  let(:domain_fact_chains) do
    [
      TransactionChains::Mail::VpsDatasetExpanded,
      TransactionChains::User::Create
    ]
  end

  let(:immediate_observation_chains) do
    [
      TransactionChains::IncidentReport::Reply,
      TransactionChains::IncidentReport::Send,
      TransactionChains::SecurityAdvisories::Mail
    ]
  end

  let(:structural_chains) do
    {
      TransactionChains::DatasetInPool::DetachBackupHeads =>
        'a mutation always appends a confirmation NoOp',
      TransactionChains::EventDelivery::Email =>
        'an empty chain means that no delivery transaction was needed',
      TransactionChains::UserNamespaceMap::Disuse =>
        'the helper either appends its node transaction or does not mutate state',
      TransactionChains::UserNamespaceMap::Use =>
        'the helper either appends its node transaction or does not mutate state'
    }
  end

  def implementation(klass)
    path, = klass.instance_method(:link_chain).source_location
    File.read(path)
  end

  it 'keeps the audited API-reachable inventory explicitly allow-empty' do
    classes = resource_fact_chains +
              domain_fact_chains +
              immediate_observation_chains +
              structural_chains.keys

    expect(classes).to all(satisfy(&:allow_empty?))
    expect(classes.map(&:name)).to contain_exactly(
      'TransactionChains::DatasetInPool::DetachBackupHeads',
      'TransactionChains::DnsResolver::Destroy',
      'TransactionChains::DnsResolver::Update',
      'TransactionChains::DnsZone::CreateRecord',
      'TransactionChains::DnsZone::CreateUser',
      'TransactionChains::DnsZone::DestroyRecord',
      'TransactionChains::DnsZone::DestroyUser',
      'TransactionChains::DnsZone::SetReverseRecord',
      'TransactionChains::DnsZone::UnsetReverseRecord',
      'TransactionChains::DnsZone::Update',
      'TransactionChains::DnsZone::UpdateRecord',
      'TransactionChains::DnsZoneTransfer::Create',
      'TransactionChains::DnsZoneTransfer::Destroy',
      'TransactionChains::EventDelivery::Email',
      'TransactionChains::Export::Update',
      'TransactionChains::HostIpAddress::Destroy',
      'TransactionChains::IncidentReport::Reply',
      'TransactionChains::IncidentReport::Send',
      'TransactionChains::Ip::Update',
      'TransactionChains::Lifetimes::Wrapper',
      'TransactionChains::Mail::VpsDatasetExpanded',
      'TransactionChains::NetworkInterface::Update',
      'TransactionChains::SecurityAdvisories::Mail',
      'TransactionChains::User::Create',
      'TransactionChains::UserNamespaceMap::Disuse',
      'TransactionChains::UserNamespaceMap::Use',
      'TransactionChains::Vps::Update'
    )
  end

  it 'declares a deferred resource fact in every resource mutation chain' do
    resource_fact_chains.each do |klass|
      expect(implementation(klass)).to include('defer_resource_event!'), klass.name
    end
  end

  it 'declares an existing domain result fact in every domain mutation chain' do
    domain_fact_chains.each do |klass|
      expect(implementation(klass)).to include('defer_result_event!'), klass.name
    end
  end

  it 'retains immediate facts only for already-persisted observations' do
    immediate_observation_chains.each do |klass|
      expect(implementation(klass)).to match(/(?:route|prepare)_event!/), klass.name
    end
  end

  it 'documents helpers whose empty path cannot mutate persistent state' do
    expect(structural_chains.values).to all(be_present)
  end
end
