# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User write actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    ensure_mail_template('user_create')
    ensure_mail_template('user_soft_delete')
    ensure_user_infra
  end

  def index_path
    vpath('/users')
  end

  def show_path(id)
    vpath("/users/#{id}")
  end

  def current_path
    vpath('/users/current')
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

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def user_obj
    json.dig('response', 'user') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def login_from(obj)
    obj['login'] || obj['username'] || obj['name']
  end

  def unique_login(prefix)
    safe_prefix = prefix.tr('_', '-')
    "#{safe_prefix}-#{SecureRandom.hex(4)}"
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

  def ensure_user_infra
    env = SpecSeed.environment

    location = Location.find_or_create_by!(label: 'Spec Location') do |loc|
      loc.environment = env
      loc.domain = 'spec-location.test'
      loc.has_ipv6 = false
      loc.remote_console_server = ''
    end

    node = Node.find_or_create_by!(name: 'spec-node') do |n|
      n.location = location
      n.ip_addr = '192.0.2.10'
      n.cpus = 2
      n.total_memory = 1024
      n.total_swap = 1024
      n.role = :node
      n.hypervisor_type = :vpsadminos
      n.max_vps = 10
      n.active = true
    end

    NodeCurrentStatus.find_or_create_by!(node: node) do |st|
      st.vpsadmin_version = 'test'
      st.kernel = 'test'
      st.update_count = 1
    end

    pool = Pool.find_by(label: 'Spec Primary Pool')

    if pool.nil?
      Pool.create!(
        {
          label: 'Spec Primary Pool',
          node: node,
          filesystem: 'specpool',
          role: :primary,
          max_datasets: 10,
          is_open: true
        },
        {}
      )
    end

    diskspace = ClusterResource.find_by!(name: 'diskspace')
    personal_pkg = ClusterResourcePackage.find_by(user: SpecSeed.admin, environment: env)
    personal_pkg ||= ClusterResourcePackage.create!(
      user: SpecSeed.admin,
      environment: env,
      label: 'Spec Default Package'
    )

    item = ClusterResourcePackageItem.find_by(
      cluster_resource_package: personal_pkg,
      cluster_resource: diskspace
    )

    if item
      item.update!(value: 300 * 1024)
    else
      ClusterResourcePackageItem.create!(
        cluster_resource_package: personal_pkg,
        cluster_resource: diskspace,
        value: 300 * 1024
      )
    end

    DefaultUserClusterResourcePackage.find_or_create_by!(
      environment: env,
      cluster_resource_package: personal_pkg
    )

    ensure_user_namespace_blocks
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

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes user write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include('user#create', 'user#update', 'user#delete')
    end
  end

  describe 'Create' do
    let(:password) { 'newsecret' }
    let(:login) { unique_login('spec-create') }
    let(:payload) do
      {
        user: {
          login: login,
          full_name: 'Spec Create User',
          email: 'spec_create@test.invalid',
          level: 1,
          vps: false,
          password: password,
          language: SpecSeed.language.id,
          enable_basic_auth: true
        }
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a user with basic auth' do
      as(SpecSeed.admin) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(true), last_response.body
      expect(login_from(user_obj)).to eq(login)

      created = User.find_by(login: login)
      expect(created).not_to be_nil

      clear_login
      basic_authorize(login, password)
      json_get current_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(login_from(user_obj)).to eq(login)
    ensure
      clear_login
    end

    it 'returns validation errors for missing login' do
      as(SpecSeed.admin) { json_post index_path, user: payload[:user].except(:login) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('login')
    end

    it 'returns validation errors for duplicate login' do
      as(SpecSeed.admin) do
        json_post index_path, user: payload[:user].merge(login: SpecSeed.user.login)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('login')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(SpecSeed.user.id), user: { mailer_enabled: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to update themselves' do
      new_value = !SpecSeed.user.mailer_enabled

      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: { mailer_enabled: new_value }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_obj['mailer_enabled']).to eq(new_value)
      expect(SpecSeed.user.reload.mailer_enabled).to eq(new_value)
    end

    it 'rejects users updating another account' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.other_user.id), user: { mailer_enabled: false }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update another user' do
      as(SpecSeed.admin) do
        json_put show_path(SpecSeed.other_user.id), user: { full_name: 'Spec Updated' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_obj['full_name']).to eq('Spec Updated')
      expect(User.find(SpecSeed.other_user.id).full_name).to eq('Spec Updated')
    end

    it 'does not allow non-admin to change protected fields' do
      original_level = SpecSeed.user.level

      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: { level: 99 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(SpecSeed.user.reload.level).to eq(original_level)
    end

    it 'returns validation errors for short new_password' do
      as(SpecSeed.admin) do
        json_put show_path(SpecSeed.other_user.id), user: { new_password: 'short' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('new_password')
    end
  end

  describe 'Password change' do
    let(:new_password) { 'newsecret1' }

    it 'allows users to change their password with the current password' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: {
          password: SpecSeed::PASSWORD,
          new_password: new_password,
          logout_sessions: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      clear_login
      basic_authorize('user', new_password)
      json_get current_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(login_from(user_obj)).to eq('user')
    ensure
      clear_login
    end

    it 'rejects password change with wrong current password' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: {
          password: 'wrong-password',
          new_password: new_password,
          logout_sessions: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('password')

      clear_login
      basic_authorize('user', SpecSeed::PASSWORD)
      json_get current_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(login_from(user_obj)).to eq('user')
    ensure
      clear_login
    end

    it 'allows admin to set another user password' do
      as(SpecSeed.admin) do
        json_put show_path(SpecSeed.other_user.id), user: {
          new_password: new_password,
          logout_sessions: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      clear_login
      basic_authorize(SpecSeed.other_user.login, new_password)
      json_get current_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(login_from(user_obj)).to eq(SpecSeed.other_user.login)
    ensure
      clear_login
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(SpecSeed.other_user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(SpecSeed.other_user.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to soft-delete a user' do
      target = SpecSeed.other_user

      as(SpecSeed.admin) { json_delete show_path(target.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      record = User.including_deleted.find(target.id)
      expect(record.current_object_state&.state).to eq('soft_delete')

      clear_login
      basic_authorize(target.login, SpecSeed::PASSWORD)
      json_get current_path

      pending('Soft-deleted users can still authenticate until the state change chain runs')
      expect(last_response.status).to be_in([401, 403])
    ensure
      clear_login
    end
  end
end
