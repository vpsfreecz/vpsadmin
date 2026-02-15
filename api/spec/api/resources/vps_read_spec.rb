# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.location
    SpecSeed.other_location
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/vpses')
  end

  def show_path(id)
    vpath("/vpses/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
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

  def json_delete(path, payload = nil)
    if payload
      delete path, JSON.dump(payload), {
        'CONTENT_TYPE' => 'application/json'
      }
    else
      delete path, {}, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end
  end

  def vps_list
    list = json.dig('response', 'vpses') || json['response'] || []
    return list if list.is_a?(Array)

    list['vpses'] || []
  end

  def vps_obj
    json.dig('response', 'vps') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
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

  describe 'API description' do
    it 'includes vps read endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('vps#index', 'vps#show')
    end
  end

  describe 'Index' do
    let!(:user_vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps') }
    let!(:other_vps) { create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'spec-other-vps') }

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only own VPSes for users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = vps_list.map { |row| row['id'] }
      expect(ids).to include(user_vps.id)
      expect(ids).not_to include(other_vps.id)
    end

    it 'shows all VPSes for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = vps_list.map { |row| row['id'] }
      expect(ids).to include(user_vps.id, other_vps.id)
    end

    it 'filters by hostname' do
      as(SpecSeed.admin) do
        json_get index_path, vps: { hostname_exact: user_vps.hostname }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = vps_list.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_vps.id)
    end

    it 'does not allow users to broaden access with user filter' do
      as(SpecSeed.user) do
        json_get index_path, vps: { user: SpecSeed.other_user.id }
      end

      expect_status(200)
      if json['status']
        ids = vps_list.map { |row| row['id'] }
        expect(ids).to contain_exactly(user_vps.id)
      else
        expect(response_message).to be_a(String)
      end
    end
  end

  describe 'Show' do
    let!(:user_vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-show-vps') }

    it 'rejects unauthenticated access' do
      json_get show_path(user_vps.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owners to see their VPS' do
      as(SpecSeed.user) { json_get show_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(vps_obj['id']).to eq(user_vps.id)
      expect(vps_obj['hostname']).to eq(user_vps.hostname)
    end

    it 'hides other users VPSes' do
      as(SpecSeed.other_user) { json_get show_path(user_vps.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to see any VPS' do
      as(SpecSeed.admin) { json_get show_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(vps_obj['id']).to eq(user_vps.id)
    end
  end

  private

  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  def pool_for_node(node)
    return SpecSeed.other_pool if node.id == SpecSeed.other_node.id

    SpecSeed.pool
  end

  def create_dataset_in_pool!(pool:, user: SpecSeed.user)
    dataset = nil

    with_current_user(SpecSeed.admin) do
      dataset = Dataset.create!(
        name: "spec-#{SecureRandom.hex(4)}",
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        object_state: :active
      )
    end

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname: nil, os_template: SpecSeed.os_template,
                  dns_resolver: SpecSeed.dns_resolver, dataset_in_pool: nil)
    dataset_in_pool ||= create_dataset_in_pool!(pool: pool_for_node(node), user: user)

    vps = Vps.new(
      user: user,
      node: node,
      hostname: hostname || "spec-vps-#{SecureRandom.hex(4)}",
      os_template: os_template,
      dns_resolver: dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active,
      confirmed: :confirmed
    )

    with_current_user(SpecSeed.admin) do
      vps.save!
    end

    vps
  rescue ActiveRecord::RecordInvalid
    vps.save!(validate: false)
    vps
  end
end
