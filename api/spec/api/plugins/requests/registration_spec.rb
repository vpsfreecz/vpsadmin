# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::UserRequest::Registration', requires_plugins: :requests do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.language
    SpecSeed.location
    SpecSeed.os_template
  end

  def index_path
    vpath('/user_request/registrations')
  end

  def show_path(id)
    vpath("/user_request/registrations/#{id}")
  end

  def resolve_path(id)
    vpath("/user_request/registrations/#{id}/resolve")
  end

  def preview_path(id, token)
    vpath("/user_request/registrations/#{id}/#{token}")
  end

  def update_path(id, token)
    vpath("/user_request/registrations/#{id}/#{token}")
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

  def registrations
    json.dig('response', 'registrations') ||
      json.dig('response', 'user_request_registrations') ||
      json.dig('response', 'registration_requests') ||
      []
  end

  def registration_obj
    json.dig('response', 'registration') ||
      json.dig('response', 'user_request_registration') ||
      json.dig('response', 'registration_request') ||
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

  def unique_login(prefix)
    safe_prefix = prefix.tr('_', '-')
    "#{safe_prefix}-#{SecureRandom.hex(4)}"
  end

  def registration_payload(login: unique_login('reg'), overrides: {})
    {
      login: login,
      full_name: 'Spec Registrant',
      email: 'registrant@test.invalid',
      address: 'Spec Address 1',
      year_of_birth: 1991,
      os_template: SpecSeed.os_template.id,
      location: SpecSeed.location.id,
      currency: 'eur',
      language: SpecSeed.language.id
    }.merge(overrides)
  end

  def ensure_mail_template(template_name)
    template = MailTemplate.find_or_create_by!(name: template_name) do |tpl|
      tpl.label = template_name.tr('_', ' ').capitalize
      tpl.template_id = template_name
    end

    return if template.mail_template_translations.where(language: SpecSeed.language).exists?

    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'noreply@test.invalid',
      subject: "#{template_name} subject",
      text_plain: "#{template_name} body"
    )
  end

  def ensure_mailer_node!
    ::Node.find_or_create_by!(name: 'spec-mailer') do |node|
      node.location = SpecSeed.location
      node.role = :mailer
      node.ip_addr = '192.0.2.150'
      node.cpus = 1
      node.total_memory = 1024
      node.total_swap = 256
      node.active = true
    end
  end

  def ensure_primary_pool!
    pool = ::Pool.find_by(filesystem: 'spec_primary_pool')
    unless pool
      pool = ::Pool.new(
        filesystem: 'spec_primary_pool',
        node: SpecSeed.node,
        label: 'Spec Primary Pool',
        role: :primary,
        max_datasets: 10,
        is_open: 1
      )
      pool.save!
    end

    seed_pool_dataset_properties!(pool)
    pool
  end

  def ensure_node_current_status(node = SpecSeed.node)
    ::NodeCurrentStatus.find_or_create_by!(node:) do |st|
      st.vpsadmin_version = 'spec'
      st.kernel = 'spec'
      st.update_count = 1
    end
  end

  def ensure_default_user_diskspace!(value: 300 * 1024)
    env = SpecSeed.environment
    diskspace = ClusterResource.find_by!(name: 'diskspace')
    pkg = ClusterResourcePackage.find_or_create_by!(user: SpecSeed.admin, environment: env) do |package|
      package.label = 'Spec Default Package'
    end

    item = ClusterResourcePackageItem.find_or_create_by!(
      cluster_resource_package: pkg,
      cluster_resource: diskspace
    ) do |it|
      it.value = value
    end

    item.update!(value: value) if item.value != value

    DefaultUserClusterResourcePackage.find_or_create_by!(
      environment: env,
      cluster_resource_package: pkg
    )
  end

  def ensure_user_namespace_blocks
    return if UserNamespaceBlock.exists?

    size = 2**16
    offset = size * 2
    blocks = (1..16).map do |i|
      {
        index: i,
        offset: offset + ((i - 1) * size),
        size: size
      }
    end

    UserNamespaceBlock.insert_all!(blocks)
  end

  def build_registration(user:, state:, attrs: {})
    record = ::RegistrationRequest.new({
      user: user,
      state: state,
      api_ip_addr: '192.0.2.11',
      api_ip_ptr: 'ptr-192.0.2.11',
      login: unique_login('reg'),
      full_name: 'Spec Registrant',
      email: 'registrant@test.invalid',
      address: 'Spec Address 1',
      year_of_birth: 1990,
      os_template: SpecSeed.os_template,
      location: SpecSeed.location,
      currency: 'eur',
      language: SpecSeed.language
    }.merge(attrs))
    record.save!
    record
  end

  let(:user) { SpecSeed.user }
  let(:admin) { SpecSeed.admin }

  let!(:r_nil_user) do
    build_registration(
      user: nil,
      state: :awaiting,
      attrs: { login: unique_login('reg-nil') }
    )
  end

  let!(:r_user) do
    build_registration(
      user: user,
      state: :awaiting,
      attrs: { login: unique_login('reg-user') }
    )
  end

  let!(:r_denied) do
    build_registration(
      user: nil,
      state: :denied,
      attrs: { login: unique_login('reg-denied') }
    )
  end

  describe 'API description' do
    it 'includes user_request.registration endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'user_request.registration#index',
        'user_request.registration#show',
        'user_request.registration#create',
        'user_request.registration#resolve',
        'user_request.registration#preview',
        'user_request.registration#update'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only own requests for normal users' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = registrations.map { |row| row['id'].to_i }
      expect(ids).to eq([r_user.id])
      expect(ids).not_to include(r_nil_user.id, r_denied.id)

      registrations.each do |row|
        expect(resource_id(row['user']).to_i).to eq(user.id)
      end
    end

    it 'lists all requests for admins' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = registrations.map { |row| row['id'].to_i }
      expect(ids).to include(r_nil_user.id, r_user.id, r_denied.id)
    end

    it 'supports state filter for admins' do
      as(admin) { json_get index_path, registration: { state: 'denied' } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = registrations.map { |row| row['id'].to_i }
      expect(ids).to eq([r_denied.id])
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(r_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows own request for normal users' do
      as(user) { json_get show_path(r_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(registration_obj['id'].to_i).to eq(r_user.id)
    end

    it 'returns 404 for requests without user_id for normal users' do
      as(user) { json_get show_path(r_nil_user.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admins to view any request' do
      as(admin) { json_get show_path(r_nil_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(registration_obj['id'].to_i).to eq(r_nil_user.id)
    end
  end

  describe 'Create' do
    it 'allows public registration' do
      header 'Client-IP', '203.0.113.10'
      payload = registration_payload(login: unique_login('reg-public'))

      expect do
        json_post index_path, registration: payload
      end.to change(::RegistrationRequest, :count).by(1)

      header 'Client-IP', nil

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::RegistrationRequest.find(resource_id(registration_obj))
      expect(record.client_ip_addr).to eq('203.0.113.10')
      expect(record.client_ip_ptr).to eq('ptr-203.0.113.10')
      expect(record.api_ip_ptr).to eq("ptr-#{record.api_ip_addr}")
      expect(record.access_token).to be_present
    end

    it 'returns validation errors for invalid login format' do
      payload = registration_payload(login: 'bad login')

      json_post index_path, registration: payload

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('login')
    end

    it 'returns validation errors when org_name is set without org_id' do
      payload = registration_payload(login: unique_login('reg-org'), overrides: { org_name: 'Spec Org' })

      json_post index_path, registration: payload

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('org_id')
    end

    it 'returns validation errors for missing email' do
      payload = registration_payload(login: unique_login('reg-no-mail')).except(:email)

      json_post index_path, registration: payload

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('email')
    end
  end

  describe 'Preview' do
    it 'shows pending correction request with valid token' do
      payload = registration_payload(login: unique_login('reg-prev'))
      json_post index_path, registration: payload

      expect_status(200)
      expect(json['status']).to be(true)

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      as(admin) do
        json_post resolve_path(req.id), registration: { action: 'request_correction', reason: 'fix data' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      json_get preview_path(req.id, req.access_token)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(registration_obj['id'].to_i).to eq(req.id)
      expect(registration_obj['admin_response']).to include('fix data')
      expect(registration_obj['login']).to eq(payload[:login])
      expect(registration_obj['email']).to eq(payload[:email])
    end

    it 'returns 404 for wrong token' do
      payload = registration_payload(login: unique_login('reg-prev-bad'))
      json_post index_path, registration: payload

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      as(admin) do
        json_post resolve_path(req.id), registration: { action: 'request_correction', reason: 'fix data' }
      end

      json_get preview_path(req.id, 'badtoken')

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when request is not pending correction' do
      payload = registration_payload(login: unique_login('reg-prev-wrong-state'))
      json_post index_path, registration: payload

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      json_get preview_path(req.id, req.access_token)

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'allows updating pending correction request and resets state' do
      payload = registration_payload(login: unique_login('reg-update'))
      json_post index_path, registration: payload

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      as(admin) do
        json_post resolve_path(req.id), registration: { action: 'request_correction', reason: 'fix data' }
      end

      mail_id = req.reload.last_mail_id

      updated_payload = registration_payload(
        login: payload[:login],
        overrides: { email: 'updated@test.invalid' }
      )

      json_put update_path(req.id, req.access_token), registration: updated_payload

      expect_status(200)
      expect(json['status']).to be(true)

      req.reload
      expect(req.state).to eq('awaiting')
      expect(req.last_mail_id).to eq(mail_id + 1)
      expect(req.email).to eq('updated@test.invalid')
    end

    it 'returns validation errors and keeps state when update fails' do
      payload = registration_payload(login: unique_login('reg-update-fail'))
      json_post index_path, registration: payload

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      as(admin) do
        json_post resolve_path(req.id), registration: { action: 'request_correction', reason: 'fix data' }
      end

      req.reload
      original_email = req.email
      original_state = req.state

      invalid_payload = registration_payload(
        login: payload[:login],
        overrides: { email: 'not-an-email' }
      )

      json_put update_path(req.id, req.access_token), registration: invalid_payload

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('email')

      req.reload
      expect(req.state).to eq(original_state)
      expect(req.email).to eq(original_email)
    end
  end

  describe 'Resolve' do
    it 'rejects unauthenticated access' do
      json_post resolve_path(r_nil_user.id), registration: { action: 'deny', reason: 'no' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post resolve_path(r_nil_user.id), registration: { action: 'deny', reason: 'no' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to deny requests' do
      req = build_registration(
        user: nil,
        state: :awaiting,
        attrs: { login: unique_login('reg-deny') }
      )

      mail_id = req.last_mail_id

      as(admin) { json_post resolve_path(req.id), registration: { action: 'deny', reason: 'no' } }

      expect_status(200)
      expect(json['status']).to be(true)

      req.reload
      expect(req.state).to eq('denied')
      expect(req.admin_id).to eq(admin.id)
      expect(req.admin_response).to eq('no')
      expect(req.last_mail_id).to eq(mail_id + 1)
    end

    it 'returns state error when denying twice' do
      req = build_registration(
        user: nil,
        state: :awaiting,
        attrs: { login: unique_login('reg-deny-twice') }
      )

      as(admin) { json_post resolve_path(req.id), registration: { action: 'deny', reason: 'no' } }

      expect_status(200)
      expect(json['status']).to be(true)

      as(admin) { json_post resolve_path(req.id), registration: { action: 'deny', reason: 'no again' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('state')
    end
  end

  describe 'Resolve approve' do
    it 'creates a user and marks request approved' do
      ensure_mailer_node!
      ensure_primary_pool!
      ensure_node_current_status(SpecSeed.node)
      ensure_mail_template('user_create')
      ensure_default_user_diskspace!
      ensure_user_namespace_blocks

      login = unique_login('reg-approve')
      payload = registration_payload(login: login)

      json_post index_path, registration: payload

      expect_status(200)
      expect(json['status']).to be(true)

      req_id = resource_id(registration_obj)
      req = ::RegistrationRequest.find(req_id)

      as(admin) do
        json_post resolve_path(req.id), registration: {
          action: 'approve',
          reason: 'ok',
          create_vps: false,
          activate: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      req = ::RegistrationRequest.find(req_id)

      expect(req.state).to eq('approved')
      expect(req.admin_id).to eq(admin.id)
      expect(::User.find_by(login: login)).not_to be_nil
    end
  end
end
