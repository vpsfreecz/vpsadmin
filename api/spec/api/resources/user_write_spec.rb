# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User write actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    %w[
      user_create
      user_soft_delete
      user_suspend
      user_resume
      user_revive
    ].each { |name| ensure_notification_template(name) }
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

  def notification_delivery_method_index_path(user_id)
    vpath("/users/#{user_id}/notification_delivery_methods")
  end

  def notification_delivery_method_path(user_id, delivery_method)
    vpath("/users/#{user_id}/notification_delivery_methods/#{delivery_method}")
  end

  def notification_rate_limit_index_path(user_id)
    vpath("/users/#{user_id}/notification_rate_limits")
  end

  def notification_rate_limit_path(user_id, limit_id)
    vpath("/users/#{user_id}/notification_rate_limits/#{limit_id}")
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

  def notification_rate_limits
    json.dig('response', 'user_notification_rate_limits') ||
      json.dig('response', 'notification_rate_limits') ||
      json['response']
  end

  def notification_rate_limit
    json.dig('response', 'user_notification_rate_limit') ||
      json.dig('response', 'notification_rate_limit') ||
      json['response']
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def login_from(obj)
    obj['login'] || obj['username'] || obj['name']
  end

  def unique_login(prefix)
    safe_prefix = prefix.tr('_', '-')
    "#{safe_prefix}-#{SecureRandom.hex(4)}"
  end

  def suspend_user!(target = SpecSeed.user)
    SpecSeed.set_password!(target, SpecSeed::PASSWORD)
    target.update!(
      object_state: :suspended,
      enable_basic_auth: true,
      enable_token_auth: false,
      enable_oauth2_auth: false,
      enable_single_sign_on: false,
      enable_new_login_notification: true,
      enable_multi_factor_auth: false,
      preferred_logout_all: false,
      preferred_session_length: 1200,
      lockout: false,
      password_reset: false
    )
    mark_user_paid_until!(target)
  end

  def ensure_notification_template(template_name)
    template = NotificationTemplate.find_or_create_by!(name: template_name) do |tpl|
      tpl.label = template_name.tr('_', ' ').capitalize
      tpl.template_id = template_name
    end

    return if template.notification_template_variants.where(language: SpecSeed.language, protocol: :email).exists?

    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'noreply@test.invalid',
      subject: "#{template_name} subject",
      text: "#{template_name} body"
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
          time_zone: 'Europe/Prague',
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
      expect(created.time_zone).to eq('Europe/Prague')

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

    it 'returns validation errors for invalid time zone' do
      as(SpecSeed.admin) do
        json_post index_path, user: payload[:user].merge(time_zone: 'Invalid/Zone')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('time_zone')
    end

    it 'passes required_diskspace when creating a user with an initial VPS' do
      diskspace = ClusterResource.find_by!(name: 'diskspace')
      record = DefaultObjectClusterResource.find_or_initialize_by(
        environment: SpecSeed.environment,
        cluster_resource: diskspace,
        class_name: 'Vps'
      )
      record.value = 20_480
      record.save!

      seen = nil
      allow(VpsAdmin::API::Operations::Node::Pick).to receive(:run) do |**kwargs|
        seen = kwargs
        Node.find_by!(name: 'spec-node')
      end

      allow(TransactionChains::User::Create).to receive(:fire) do |user, *_args|
        user.save!
        [
          TransactionChain.create!(
            name: TransactionChains::User::Create.chain_name,
            type: TransactionChains::User::Create.name,
            state: :queued,
            size: 1,
            user: SpecSeed.admin,
            user_session: nil
          ),
          user
        ]
      end

      as(SpecSeed.admin) do
        json_post index_path, user: payload[:user].merge(
          vps: true,
          environment: SpecSeed.environment.id,
          os_template: SpecSeed.os_template.id
        )
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(seen[:required_diskspace]).to eq(20_480)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(SpecSeed.user.id), user: { full_name: 'Unauthenticated Update' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to update their time zone' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: { time_zone: 'America/New_York' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_obj['time_zone']).to eq('America/New_York')
      expect(SpecSeed.user.reload.time_zone).to eq('America/New_York')
    end

    it 'normalizes empty time zone to server default' do
      SpecSeed.user.update!(time_zone: 'Europe/Prague')

      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: { time_zone: '' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_obj['time_zone']).to be_nil
      expect(SpecSeed.user.reload.time_zone).to be_nil
    end

    it 'returns validation errors for invalid updated time zone' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: { time_zone: 'Invalid/Zone' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('time_zone')
    end

    it 'denies suspended users updating authentication settings' do
      suspend_user!

      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: {
          enable_token_auth: true,
          enable_oauth2_auth: true,
          enable_single_sign_on: true,
          enable_new_login_notification: false,
          preferred_logout_all: true,
          preferred_session_length: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('Access forbidden')

      SpecSeed.user.reload
      expect(SpecSeed.user.enable_token_auth).to be(false)
      expect(SpecSeed.user.enable_oauth2_auth).to be(false)
      expect(SpecSeed.user.enable_single_sign_on).to be(false)
      expect(SpecSeed.user.enable_new_login_notification).to be(true)
      expect(SpecSeed.user.preferred_logout_all).to be(false)
      expect(SpecSeed.user.preferred_session_length).to eq(1200)
    end

    it 'rejects users updating another account' do
      as(SpecSeed.user) do
        json_put show_path(SpecSeed.other_user.id), user: { full_name: 'Spec Updated' }
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

    it 'lists effective notification delivery methods for the current user' do
      as(SpecSeed.user) do
        json_get notification_delivery_method_index_path(SpecSeed.user.id)
      end

      expect_status(200)
      methods = json.dig('response', 'user_notification_delivery_methods') ||
                json.dig('response', 'notification_delivery_methods') ||
                json['response']
      expect(methods.to_h { |v| [v.fetch('delivery_method'), v.fetch('enabled')] }).to include(
        'email' => true,
        'webhook' => true,
        'telegram' => true,
        'sms' => true
      )
    end

    it 'allows admin to update notification delivery methods' do
      as(SpecSeed.admin) do
        json_put notification_delivery_method_path(SpecSeed.other_user.id, 'webhook'), {
          notification_delivery_method: { enabled: false }
        }
      end

      expect_status(200)
      expect(json['status']).to be(true), last_response.body
      expect(SpecSeed.other_user.reload.notification_delivery_method_enabled?(:webhook)).to be(false)

      as(SpecSeed.admin) do
        json_get notification_delivery_method_path(SpecSeed.other_user.id, 'webhook')
      end

      expect_status(200)
      method = json.dig('response', 'user_notification_delivery_method') ||
               json.dig('response', 'notification_delivery_method') ||
               json['response']
      expect(method).to include(
        'delivery_method' => 'webhook',
        'enabled' => false
      )
    end

    it 'lists notification rate limits with rolling usage counts' do
      event = Event.create!(
        user: SpecSeed.user,
        event_type: 'user.test_notification',
        category: 'test',
        severity: 'info',
        subject: 'Spec rate limit usage',
        parameters: {}
      )
      delivery = EventDelivery.create!(
        event:,
        action: :webhook,
        target_kind: :custom,
        target_value: 'https://example.test/events',
        target_label: 'Spec webhook',
        state: :sent
      )
      delivery.event_delivery_attempts.create!(
        recipient_user: SpecSeed.user,
        action: :webhook,
        state: :succeeded,
        attempt_number: 1,
        started_at: Time.now - 5,
        finished_at: Time.now - 4
      )

      as(SpecSeed.user) do
        json_get notification_rate_limit_index_path(SpecSeed.user.id)
      end

      expect_status(200)
      limits_by_id = notification_rate_limits.to_h { |row| [row.fetch('id'), row] }
      expect(limits_by_id.keys).to include('webhook.minute', 'webhook.week')
      expect(limits_by_id.fetch('webhook.minute')).to include(
        'limit_count' => 60,
        'default_limit_count' => 60,
        'override_limit_count' => nil,
        'used_count' => 1,
        'remaining_count' => 59,
        'source' => 'default'
      )
      expect(limits_by_id.fetch('webhook.week')).to include(
        'limit_count' => 25_000,
        'used_count' => 1
      )
    end

    it 'allows admins to override notification rate limits' do
      as(SpecSeed.admin) do
        json_put notification_rate_limit_path(SpecSeed.other_user.id, 'webhook.week'), {
          notification_rate_limit: { limit_count: 1234 }
        }
      end

      expect_status(200)
      expect(json['status']).to be(true), last_response.body
      expect(notification_rate_limit).to include(
        'id' => 'webhook.week',
        'limit_count' => 1234,
        'default_limit_count' => 25_000,
        'override_limit_count' => 1234,
        'source' => 'override'
      )

      as(SpecSeed.admin) do
        json_get notification_rate_limit_path(SpecSeed.other_user.id, 'webhook.week')
      end

      expect_status(200)
      expect(notification_rate_limit).to include(
        'id' => 'webhook.week',
        'limit_count' => 1234,
        'source' => 'override'
      )
    end

    it 'rejects user updates to notification rate limits' do
      as(SpecSeed.user) do
        json_put notification_rate_limit_path(SpecSeed.user.id, 'sms.minute'), {
          notification_rate_limit: { limit_count: 1 }
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
      expect(SpecSeed.user.user_notification_rate_limits).to be_empty
    end

    it 'rejects user updates to notification delivery methods' do
      as(SpecSeed.user) do
        json_put notification_delivery_method_path(SpecSeed.user.id, 'sms'), {
          notification_delivery_method: { enabled: false }
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
      expect(SpecSeed.user.reload.notification_delivery_method_enabled?(:sms)).to be(true)
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

    it 'denies suspended users changing their password' do
      suspend_user!

      as(SpecSeed.user) do
        json_put show_path(SpecSeed.user.id), user: {
          password: SpecSeed::PASSWORD,
          new_password: new_password,
          logout_sessions: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('Access forbidden')

      clear_login
      basic_authorize(SpecSeed.user.login, new_password)
      json_get current_path
      expect(last_response.status).not_to eq(200)

      clear_login
      basic_authorize(SpecSeed.user.login, SpecSeed::PASSWORD)
      json_get current_path
      expect_status(200)
      expect(json['status']).to be(true)
      expect(login_from(user_obj)).to eq(SpecSeed.user.login)
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

  describe 'Lifetimes::Resource' do
    let(:admin) { SpecSeed.admin }
    let(:target) { SpecSeed.other_user }

    before do
      allow(User).to receive(:including_deleted) { User.unscoped }
    end

    def set_state(user, state)
      User.unscoped.find(user.id).record_object_state_change(
        state.to_sym,
        reason: 'spec setup',
        user: admin
      )
    end

    def last_log(user)
      ObjectState.where(class_name: 'User', row_id: user.id).order(:id).last
    end

    def log_count(user)
      ObjectState.where(class_name: 'User', row_id: user.id).count
    end

    it 'updates expiration_date without changing state' do
      set_state(target, :active)
      expiration = Time.utc(2040, 1, 1, 12, 0, 0)

      as(admin) do
        json_put show_path(target.id), user: {
          expiration_date: expiration.strftime('%Y-%m-%dT%H:%M:%SZ')
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      record = User.unscoped.find(target.id)
      expect(record.object_state).to eq('active')
      expect(record.expiration_date.to_i).to eq(expiration.to_i)
    end

    states = %w[active suspended soft_delete hard_delete deleted]

    states.each do |from|
      states.each do |to|
        next if from == to

        it "handles #{from} -> #{to} transitions" do
          set_state(target, from)
          before_count = log_count(target)

          as(admin) do
            json_put show_path(target.id), user: {
              object_state: to,
              change_reason: "spec #{from} -> #{to}"
            }
          end

          expect_status(200)

          supported = lifetimes_transition_supported_for?(User, from, to)

          if supported
            expect(json['status']).to be(true)
            expect(log_count(target)).to eq(before_count + 1)
            expect(last_log(target).state).to eq(to)
          else
            expect(json['status']).to be(false)
            expect(log_count(target)).to eq(before_count)

            if lifetimes_transition_supported?(from, to)
              expect(response_message).to include('not implemented')
            else
              expect(response_message).to include('cannot leave state')
            end
          end
        end
      end
    end
  end
end
