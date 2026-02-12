# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::DnsResolver' do
  let(:dns_resolver) { SpecSeed.dns_resolver }
  let(:other_dns_resolver) { SpecSeed.other_dns_resolver }

  before do
    header 'Accept', 'application/json'
    dns_resolver
    other_dns_resolver
  end

  def index_path
    vpath('/dns_resolvers')
  end

  def show_path(id)
    vpath("/dns_resolvers/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def resolvers
    json.dig('response', 'dns_resolvers')
  end

  def resolver_obj
    json.dig('response', 'dns_resolver')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to list DNS resolvers' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(resolvers).to be_an(Array)

      ids = resolvers.map { |row| row['id'] }
      expect(ids).to include(dns_resolver.id, other_dns_resolver.id)

      row = resolvers.find { |item| item['id'] == dns_resolver.id }
      expect(row).to include('id', 'ip_addr', 'label', 'is_universal', 'location')
      expect(row['label']).to eq(dns_resolver.label)
      expect(row['ip_addr']).to eq(dns_resolver.addrs)
      expect(row['is_universal']).to be(true)
      expect(row['location']).to be_nil

      other_row = resolvers.find { |item| item['id'] == other_dns_resolver.id }
      expect(other_row['is_universal']).to be(false)
      expect(resource_id(other_row['location'])).to eq(other_dns_resolver.location_id)
    end

    it 'allows support to list DNS resolvers' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(resolvers).to be_an(Array)
    end

    it 'allows admins to list DNS resolvers' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(resolvers).to be_an(Array)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, dns_resolver: { limit: 1 } }

      expect_status(200)
      expect(resolvers.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = DnsResolver.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, dns_resolver: { from_id: boundary } }

      expect_status(200)
      ids = resolvers.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(DnsResolver.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(dns_resolver.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show DNS resolvers' do
      as(SpecSeed.user) { json_get show_path(dns_resolver.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(resolver_obj['id']).to eq(dns_resolver.id)
      expect(resolver_obj['label']).to eq(dns_resolver.label)
      expect(resolver_obj['ip_addr']).to eq(dns_resolver.addrs)
      expect(resolver_obj['is_universal']).to be(true)
      expect(resolver_obj['location']).to be_nil
    end

    it 'allows support to show DNS resolvers' do
      as(SpecSeed.support) { json_get show_path(dns_resolver.id) }

      expect_status(200)
      expect(resolver_obj['id']).to eq(dns_resolver.id)
    end

    it 'allows admins to show DNS resolvers' do
      as(SpecSeed.admin) { json_get show_path(dns_resolver.id) }

      expect_status(200)
      expect(resolver_obj['id']).to eq(dns_resolver.id)
    end

    it 'returns 404 for unknown DNS resolver' do
      missing = DnsResolver.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
