# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserRequest::Change', requires_plugins: :requests do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
  end

  def index_path
    vpath('/user_request/changes')
  end

  def show_path(id)
    vpath("/user_request/changes/#{id}")
  end

  def resolve_path(id)
    vpath("/user_request/changes/#{id}/resolve")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def changes
    json.dig('response', 'changes') ||
      json.dig('response', 'user_request_changes') ||
      json.dig('response', 'change_requests') ||
      []
  end

  def change_obj
    json.dig('response', 'change') ||
      json.dig('response', 'user_request_change') ||
      json.dig('response', 'change_request') ||
      json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def resource_id(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def build_change(user:, state:, attrs: {})
    record = ::ChangeRequest.new({
      user: user,
      state: state,
      api_ip_addr: '192.0.2.10',
      api_ip_ptr: 'ptr-192.0.2.10',
      change_reason: 'Need update',
      full_name: 'Spec User'
    }.merge(attrs))
    record.save!
    record
  end

  def change_payload(overrides = {})
    {
      change_reason: 'Spec change reason',
      full_name: 'Spec Changed'
    }.merge(overrides)
  end

  let(:user) { SpecSeed.user }
  let(:admin) { SpecSeed.admin }

  let!(:c_user_awaiting) do
    build_change(
      user: user,
      state: :awaiting,
      attrs: {
        change_reason: 'Spec change 1',
        full_name: 'Spec User One'
      }
    )
  end

  let!(:c_user_approved) do
    build_change(
      user: user,
      state: :approved,
      attrs: {
        change_reason: 'Spec change 2',
        full_name: 'Spec User Two'
      }
    )
  end

  let!(:c_other) do
    build_change(
      user: SpecSeed.other_user,
      state: :awaiting,
      attrs: {
        change_reason: 'Spec change other',
        full_name: 'Spec Other'
      }
    )
  end

  describe 'API description' do
    it 'includes user_request.change endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user_request.change#index',
        'user_request.change#show',
        'user_request.change#create',
        'user_request.change#resolve'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists own requests for normal users in descending id order' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = changes.map { |row| row['id'].to_i }
      expect(ids).to eq([c_user_approved.id, c_user_awaiting.id])
      expect(ids).not_to include(c_other.id)

      changes.each do |row|
        expect(resource_id(row['user']).to_i).to eq(user.id)
      end
    end

    it 'supports state filter for normal users' do
      as(user) { json_get index_path, change: { state: 'approved' } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = changes.map { |row| row['id'].to_i }
      expect(ids).to eq([c_user_approved.id])
    end

    it 'lists all requests for admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = changes.map { |row| row['id'].to_i }
      expect(ids).to eq([c_other.id, c_user_approved.id, c_user_awaiting.id])
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(c_user_awaiting.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own request for normal users' do
      as(user) { json_get show_path(c_user_awaiting.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      expect(change_obj).to include(
        'id',
        'state',
        'api_ip_addr',
        'api_ip_ptr',
        'created_at',
        'updated_at',
        'change_reason'
      )
      expect(change_obj['id'].to_i).to eq(c_user_awaiting.id)
    end

    it 'returns 404 for other user requests' do
      as(user) { json_get show_path(c_other.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view any request' do
      as(admin) { json_get show_path(c_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(change_obj['id'].to_i).to eq(c_other.id)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, change: change_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to create change requests' do
      header 'Client-IP', '203.0.113.9'

      expect do
        as(user) { json_post index_path, change: change_payload }
      end.to change(::ChangeRequest, :count).by(1)

      header 'Client-IP', nil

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::ChangeRequest.order(:id).last
      expect(record.user_id).to eq(user.id)
      expect(record.change_reason).to eq('Spec change reason')
      expect(record.client_ip_addr).to eq('203.0.113.9')
      expect(record.client_ip_ptr).to eq('ptr-203.0.113.9')
      expect(record.api_ip_ptr).to eq("ptr-#{record.api_ip_addr}")
    end

    it 'returns validation errors for missing change_reason' do
      as(user) { json_post index_path, change: change_payload.except(:change_reason) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('change_reason')
    end

    it 'returns validation errors when no changes are provided' do
      as(user) { json_post index_path, change: { change_reason: 'Missing changes' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('full_name', 'email', 'address')
    end
  end

  describe 'Resolve' do
    it 'rejects unauthenticated access' do
      json_post resolve_path(c_user_awaiting.id), change: { action: 'approve', reason: 'ok' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post resolve_path(c_user_awaiting.id), change: { action: 'approve', reason: 'ok' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to approve and applies changes' do
      req = build_change(
        user: user,
        state: :awaiting,
        attrs: {
          change_reason: 'Spec approve',
          full_name: 'Spec Changed'
        }
      )

      mail_id = req.last_mail_id

      as(admin) { json_post resolve_path(req.id), change: { action: 'approve', reason: 'ok' } }

      expect_status(200)
      expect(json['status']).to be(true)

      req.reload
      expect(req.state).to eq('approved')
      expect(req.admin_id).to eq(admin.id)
      expect(req.admin_response).to eq('ok')
      expect(req.last_mail_id).to eq(mail_id + 1)
      expect(user.reload.full_name).to eq('Spec Changed')
    end

    it 'returns state error when approving twice' do
      req = build_change(
        user: user,
        state: :awaiting,
        attrs: {
          change_reason: 'Spec approve again',
          full_name: 'Spec Changed'
        }
      )

      as(admin) { json_post resolve_path(req.id), change: { action: 'approve', reason: 'ok' } }

      expect_status(200)
      expect(json['status']).to be(true)

      as(admin) { json_post resolve_path(req.id), change: { action: 'approve', reason: 'again' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('state')
    end
  end
end
