# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::DnsResolver write actions' do # rubocop:disable RSpec/DescribeClass
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

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def resolver_obj
    json.dig('response', 'dns_resolver') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def action_input_params(resource_name, action_name)
    header 'Accept', 'application/json'
    options vpath('/')
    expect(last_response.status).to eq(200)

    data = json
    data = data['response'] if data.is_a?(Hash) && data['response'].is_a?(Hash)

    resources = data['resources'] || {}
    action = resources.dig(resource_name.to_s, 'actions', action_name.to_s) || {}
    action.dig('input', 'parameters') || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def random_ipv4
    "192.0.2.#{200 + SecureRandom.random_number(40)}"
  end

  def minimal_resolver_payload(label: nil, overrides: {})
    suffix = SecureRandom.hex(4)

    payload = {
      ip_addr: random_ipv4,
      label: label || "Spec DNS #{suffix}",
      is_universal: true
    }

    payload.merge!(overrides)
    payload
  end

  def create_resolver!(label_prefix: 'spec_dns_del')
    suffix = SecureRandom.hex(4)

    DnsResolver.create!(
      addrs: random_ipv4,
      label: "#{label_prefix}_#{suffix}",
      is_universal: true,
      location: nil,
      ip_version: 4
    )
  end

  describe 'API description' do
    it 'includes dns_resolver write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('dns_resolver#create', 'dns_resolver#update', 'dns_resolver#delete')
    end

    it 'documents dns_resolver write inputs' do
      create_params = action_input_params('dns_resolver', 'create')
      update_params = action_input_params('dns_resolver', 'update')
      delete_params = action_input_params('dns_resolver', 'delete')

      expect(create_params.keys).to include('ip_addr', 'label', 'is_universal', 'location')
      expect(update_params.keys).to include('ip_addr', 'label', 'is_universal', 'location')
      expect(delete_params.keys).to include('force')
    end
  end

  describe 'Create' do
    let(:payload) { minimal_resolver_payload }

    it 'rejects unauthenticated access' do
      json_post index_path, dns_resolver: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, dns_resolver: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, dns_resolver: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create with minimal payload' do
      as(SpecSeed.admin) { json_post index_path, dns_resolver: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(resolver_obj).to be_a(Hash)
      expect(resolver_obj['label']).to eq(payload[:label])
      expect(resolver_obj['ip_addr']).to eq(payload[:ip_addr])
      expect(resolver_obj['is_universal']).to be(true)
      expect(resolver_obj['location']).to be_nil

      record = DnsResolver.find_by!(label: payload[:label])
      expect(record.addrs).to eq(payload[:ip_addr])
      expect(record.is_universal).to be(true)
      expect(record.location_id).to be_nil
    end

    it 'returns validation errors for missing label' do
      as(SpecSeed.admin) { json_post index_path, dns_resolver: payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing ip_addr' do
      as(SpecSeed.admin) { json_post index_path, dns_resolver: payload.except(:ip_addr) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('ip_addr')
    end

    it 'returns validation errors for invalid location settings' do
      invalid_payload = payload.merge(is_universal: false)
      as(SpecSeed.admin) { json_post index_path, dns_resolver: invalid_payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('is_universal')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(dns_resolver.id), dns_resolver: { label: 'Spec DNS Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_put show_path(dns_resolver.id), dns_resolver: { label: 'Spec DNS Updated' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_put show_path(dns_resolver.id), dns_resolver: { label: 'Spec DNS Updated' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update and returns the object' do
      ensure_signer_unlocked!

      new_label = "Spec DNS Updated #{SecureRandom.hex(3)}"
      new_addr = random_ipv4

      as(SpecSeed.admin) do
        json_put show_path(dns_resolver.id), dns_resolver: {
          label: new_label,
          ip_addr: new_addr
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(resolver_obj).to be_a(Hash)
      expect(resolver_obj['label']).to eq(new_label)
      expect(resolver_obj['ip_addr']).to eq(new_addr)

      record = DnsResolver.find(dns_resolver.id)
      expect(record.label).to eq(new_label)
      expect(record.addrs).to eq(new_addr)
    end

    it 'returns validation errors for invalid location settings' do
      ensure_signer_unlocked!

      as(SpecSeed.admin) do
        json_put show_path(dns_resolver.id), dns_resolver: { is_universal: false }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('is_universal')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      resolver = create_resolver!
      json_delete show_path(resolver.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      resolver = create_resolver!
      as(SpecSeed.user) { json_delete show_path(resolver.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      resolver = create_resolver!
      as(SpecSeed.support) { json_delete show_path(resolver.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a resolver' do
      ensure_signer_unlocked!

      resolver = create_resolver!
      as(SpecSeed.admin) { json_delete show_path(resolver.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(DnsResolver.where(id: resolver.id)).to be_empty
    end

    it 'returns 404 for unknown resolver' do
      missing = DnsResolver.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
