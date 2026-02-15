# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS write actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.location
    SpecSeed.other_location
    SpecSeed.environment
    SpecSeed.other_environment
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_family
    SpecSeed.os_template
    SpecSeed.dns_resolver
    SpecSeed.other_dns_resolver
  end

  def index_path
    vpath('/vpses')
  end

  def show_path(id)
    vpath("/vpses/#{id}")
  end

  def set_maintenance_path(id)
    vpath("/vpses/#{id}/set_maintenance")
  end

  def start_path(id)
    vpath("/vpses/#{id}/start")
  end

  def stop_path(id)
    vpath("/vpses/#{id}/stop")
  end

  def restart_path(id)
    vpath("/vpses/#{id}/restart")
  end

  def passwd_path(id)
    vpath("/vpses/#{id}/passwd")
  end

  def boot_path(id)
    vpath("/vpses/#{id}/boot")
  end

  def reinstall_path(id)
    vpath("/vpses/#{id}/reinstall")
  end

  def migrate_path(id)
    vpath("/vpses/#{id}/migrate")
  end

  def clone_path(id)
    vpath("/vpses/#{id}/clone")
  end

  def swap_with_path(id)
    vpath("/vpses/#{id}/swap_with")
  end

  def replace_path(id)
    vpath("/vpses/#{id}/replace")
  end

  def deploy_public_key_path(id)
    vpath("/vpses/#{id}/deploy_public_key")
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

  def random_ipv4
    "192.0.2.#{200 + SecureRandom.random_number(40)}"
  end

  def fake_chain!(klass)
    TransactionChain.create!(
      name: klass.chain_name,
      type: klass.name,
      state: :queued,
      size: 1,
      user: User.current,
      user_session: UserSession.current
    )
  end

  describe 'API description' do
    it 'includes vps write endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'vps#create',
        'vps#update',
        'vps#delete',
        'vps#set_maintenance',
        'vps#start',
        'vps#stop',
        'vps#restart',
        'vps#passwd',
        'vps#boot',
        'vps#reinstall',
        'vps#migrate',
        'vps#clone',
        'vps#swap_with',
        'vps#replace',
        'vps#deploy_public_key'
      )
    end
  end

  describe 'Create' do
    let(:hostname) { "spec-create-#{SecureRandom.hex(4)}" }
    let(:payload) do
      {
        user: SpecSeed.other_user.id,
        node: SpecSeed.node.id,
        hostname: hostname,
        os_template: SpecSeed.os_template.id,
        dns_resolver: SpecSeed.dns_resolver.id,
        cpu: 2,
        memory: 1024,
        swap: 512,
        diskspace: 10_000
      }
    end

    before do
      allow(TransactionChains::Vps::Create).to receive(:fire) do |vps, _opts|
        vps.dataset_in_pool ||= create_dataset_in_pool!(pool: pool_for_node(vps.node), user: vps.user)
        vps.confirmed = :confirmed
        vps.save!
        [fake_chain!(TransactionChains::Vps::Create), vps]
      end
    end

    it 'rejects unauthenticated access' do
      json_post index_path, vps: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create VPS for another user' do
      expect do
        as(SpecSeed.admin) { json_post index_path, vps: payload }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = Vps.find_by!(hostname: hostname)
      expect(record.user_id).to eq(SpecSeed.other_user.id)
      expect(record.node_id).to eq(SpecSeed.node.id)
    end

    it 'returns validation errors for missing hostname' do
      as(SpecSeed.admin) { json_post index_path, vps: payload.except(:hostname) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('hostname')
    end

    it 'rejects user namespace map belonging to a different user' do
      user_ns = UserNamespace.create!(
        user: SpecSeed.user,
        block_count: 0,
        offset: 100_000,
        size: 1_000
      )
      user_map = UserNamespaceMap.create_direct!(user_ns, 'Spec map')

      as(SpecSeed.admin) do
        json_post index_path, vps: payload.merge(user_namespace_map: user_map.id)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('user namespace map has to belong to VPS owner')
    end

    context 'when non-admin' do
      let(:user_payload) do
        {
          environment: SpecSeed.environment.id,
          hostname: "spec-user-create-#{SecureRandom.hex(4)}",
          os_template: SpecSeed.os_template.id,
          dns_resolver: SpecSeed.dns_resolver.id,
          cpu: 2,
          memory: 1024,
          swap: 512,
          diskspace: 10_000
        }
      end

      before do
        allow(VpsAdmin::API::Operations::Node::Pick).to receive(:run).and_return(SpecSeed.node)
      end

      it 'requires environment or location' do
        as(SpecSeed.user) { json_post index_path, vps: user_payload.except(:environment) }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to include('provide either an environment or a location')
      end

      it 'rejects when user cannot create in environment' do
        set_env_config!(
          user: SpecSeed.user,
          environment: SpecSeed.environment,
          attrs: { can_create_vps: false }
        )

        as(SpecSeed.user) { json_post index_path, vps: user_payload }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to include('insufficient permission to create a VPS in this environment')
      end

      it 'creates VPS for current user' do
        set_env_config!(
          user: SpecSeed.user,
          environment: SpecSeed.environment,
          attrs: { can_create_vps: true, max_vps_count: 10 }
        )

        expect do
          as(SpecSeed.user) { json_post index_path, vps: user_payload }
        end.to change(TransactionChain, :count).by(1)

        expect_status(200)
        expect(json['status']).to be(true)

        record = Vps.find_by!(hostname: user_payload[:hostname])
        expect(record.user_id).to eq(SpecSeed.user.id)
        expect(record.node_id).to eq(SpecSeed.node.id)
      end

      it 'ignores user and node overrides' do
        set_env_config!(
          user: SpecSeed.user,
          environment: SpecSeed.environment,
          attrs: { can_create_vps: true, max_vps_count: 10 }
        )

        overridden = user_payload.merge(user: SpecSeed.other_user.id, node: SpecSeed.other_node.id)
        as(SpecSeed.user) { json_post index_path, vps: overridden }

        expect_status(200)
        if json['status']
          record = Vps.find_by!(hostname: overridden[:hostname])
          expect(record.user_id).to eq(SpecSeed.user.id)
          expect(record.node_id).to eq(SpecSeed.node.id)
        else
          expect(response_message).to be_a(String)
        end
      end
    end
  end

  describe 'Update' do
    before do
      allow(TransactionChains::Vps::Update).to receive(:fire) do |target, attrs|
        target.assign_attributes(attrs)
        target.save!(validate: false)
        [fake_chain!(TransactionChains::Vps::Update), nil]
      end
    end

    it 'rejects unauthenticated access' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      json_put show_path(vps.id), vps: { info: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides updates for other users' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.other_user) { json_put show_path(vps.id), vps: { info: 'Updated' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows owner to update start_menu_timeout' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.user) { json_put show_path(vps.id), vps: { start_menu_timeout: 10 } }

      expect_status(200)
      expect(json['status']).to be(true)

      vps.reload
      expect(vps.start_menu_timeout).to eq(10)
    end

    it 'rejects empty payloads' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.user) { json_put show_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide at least one attribute to update')
    end

    it 'keeps hostname when manage_hostname is false' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-host')

      as(SpecSeed.user) do
        json_put show_path(vps.id), vps: { manage_hostname: false, hostname: 'new-host' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      vps.reload
      expect(vps.manage_hostname).to be(false)
      expect(vps.hostname).to eq('spec-host')
    end

    it 'requires hostname when manage_hostname is true' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.user) { json_put show_path(vps.id), vps: { manage_hostname: true, hostname: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('hostname')
    end

    it 'rejects DNS resolver from a different location' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      resolver = create_dns_resolver!(is_universal: false, location: SpecSeed.other_location)

      as(SpecSeed.user) { json_put show_path(vps.id), vps: { dns_resolver: resolver.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('not available')
    end

    it 'rejects swap on vpsAdminOS nodes without swap' do
      node = create_node!(
        name_prefix: 'spec-noswap',
        location: SpecSeed.location,
        role: :node,
        hypervisor_type: :vpsadminos,
        total_swap: 0
      )
      vps = create_vps!(user: SpecSeed.user, node: node)

      as(SpecSeed.user) { json_put show_path(vps.id), vps: { swap: 128 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('swap is not available')
    end

    it 'rejects user namespace map from another user' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      other_ns = UserNamespace.create!(
        user: SpecSeed.other_user,
        block_count: 0,
        offset: 200_000,
        size: 1_000
      )
      other_map = UserNamespaceMap.create_direct!(other_ns, 'Other map')

      as(SpecSeed.user) do
        json_put show_path(vps.id), vps: { user_namespace_map: other_map.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('belongs to a different user')
    end

    it 'rejects lowering memory below current usage' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      allocate_vps_resource!(vps, :memory, 1024)
      VpsCurrentStatus.create!(
        vps: vps,
        status: true,
        is_running: true,
        used_memory: 900,
        update_count: 1
      )

      as(SpecSeed.user) { json_put show_path(vps.id), vps: { memory: 800 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('cannot lower memory limit below current usage')
    end

    it 'allows admin to change VPS owner' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.admin) { json_put show_path(vps.id), vps: { user: SpecSeed.other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(vps.reload.user_id).to eq(SpecSeed.other_user.id)
    end

    it 'rejects resource changes when changing owner' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.admin) do
        json_put show_path(vps.id), vps: { user: SpecSeed.other_user.id, memory: 2048 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('resources cannot be changed when changing VPS owner')
    end
  end

  describe 'Delete' do
    before do
      allow_any_instance_of(Vps).to receive(:set_object_state) do |inst, state, **_kwargs| # rubocop:disable RSpec/AnyInstance
        inst.update!(object_state: state)
        [fake_chain!(TransactionChains::Vps::SoftDelete), nil]
      end
    end

    it 'rejects unauthenticated access' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      json_delete show_path(vps.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides deletes for other users' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.other_user) { json_delete show_path(vps.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'soft deletes for owner' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.user) { json_delete show_path(vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(vps.reload.object_state).to eq('soft_delete')
    end

    it 'soft deletes for admin by default' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.admin) { json_delete show_path(vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(vps.reload.object_state).to eq('soft_delete')
    end

    it 'hard deletes for admin when lazy is false' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.admin) { json_delete show_path(vps.id), vps: { lazy: false } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(Vps.unscoped.find(vps.id).object_state).to eq('hard_delete')
    end

    it 'ignores lazy for non-admins' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)

      as(SpecSeed.user) { json_delete show_path(vps.id), vps: { lazy: false } }

      expect_status(200)
      if json['status']
        expect(vps.reload.object_state).to eq('soft_delete')
      else
        expect(response_message).to be_a(String)
      end
    end
  end

  describe 'SetMaintenance' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post set_maintenance_path(vps.id), vps: { lock: true, reason: 'Spec reason' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post set_maintenance_path(vps.id), vps: { lock: true, reason: 'Spec reason' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to lock maintenance' do
      as(SpecSeed.admin) do
        json_post set_maintenance_path(vps.id), vps: { lock: true, reason: 'Spec reason' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      vps.reload
      expect(vps.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:lock))
      expect(vps.maintenance_lock_reason).to eq('Spec reason')
    end

    it 'allows admin to unlock maintenance' do
      MaintenanceLock.lock_for(vps, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(vps)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(vps.id), vps: { lock: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      vps.reload
      expect(vps.maintenance_lock).to eq(MaintenanceLock.maintain_lock(:no))
      expect(vps.maintenance_lock_reason).to be_nil
    end

    it 'returns error when already locked' do
      MaintenanceLock.lock_for(vps, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(vps)

      as(SpecSeed.admin) do
        json_post set_maintenance_path(vps.id), vps: { lock: true, reason: 'Spec again' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already locked')
    end
  end

  describe 'Start' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post start_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post start_path(vps.id), vps: {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'starts VPS for owner' do
      allow(TransactionChains::Vps::Start).to receive(:fire) do |_target|
        [fake_chain!(TransactionChains::Vps::Start), nil]
      end

      expect do
        as(SpecSeed.user) { json_post start_path(vps.id), vps: {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'blocks non-admin during maintenance' do
      MaintenanceLock.lock_for(vps, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(vps)

      as(SpecSeed.user) { json_post start_path(vps.id), vps: {} }

      expect_status(423)
      expect(json['status']).to be(false)
    end

    it 'allows admin during maintenance' do
      MaintenanceLock.lock_for(vps, user: SpecSeed.admin, reason: 'Spec lock')
                     .lock!(vps)

      allow(TransactionChains::Vps::Start).to receive(:fire) do |_target|
        [fake_chain!(TransactionChains::Vps::Start), nil]
      end

      expect do
        as(SpecSeed.admin) { json_post start_path(vps.id), vps: {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Stop' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post stop_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post stop_path(vps.id), vps: {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'stops VPS for owner' do
      allow(TransactionChains::Vps::Stop).to receive(:fire) do |_target, **_kwargs|
        [fake_chain!(TransactionChains::Vps::Stop), nil]
      end

      expect do
        as(SpecSeed.user) { json_post stop_path(vps.id), vps: {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'passes force flag' do
      allow(TransactionChains::Vps::Stop).to receive(:fire).and_return(
        [fake_chain!(TransactionChains::Vps::Stop), nil]
      )

      as(SpecSeed.user) { json_post stop_path(vps.id), vps: { force: true } }

      expect(TransactionChains::Vps::Stop).to have_received(:fire).with(vps, kill: true)
      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Restart' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post restart_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post restart_path(vps.id), vps: {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'restarts VPS for owner' do
      allow(TransactionChains::Vps::Restart).to receive(:fire) do |_target, **_kwargs|
        [fake_chain!(TransactionChains::Vps::Restart), nil]
      end

      expect do
        as(SpecSeed.user) { json_post restart_path(vps.id), vps: {} }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'passes force flag' do
      allow(TransactionChains::Vps::Restart).to receive(:fire).and_return(
        [fake_chain!(TransactionChains::Vps::Restart), nil]
      )

      as(SpecSeed.user) { json_post restart_path(vps.id), vps: { force: true } }

      expect(TransactionChains::Vps::Restart).to have_received(:fire).with(vps, kill: true)
      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Passwd' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post passwd_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post passwd_path(vps.id), vps: {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns generated password' do
      seen = {}
      allow(VpsAdmin::API::Operations::Vps::Passwd).to receive(:run) do |_target, type|
        seen[:type] = type
        [fake_chain!(TransactionChains::Vps::Passwd), 'generated-password']
      end

      as(SpecSeed.user) { json_post passwd_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(true)
      password =
        json.dig('response', 'vps', 'password') ||
        json.dig('response', 'password') ||
        json['password']
      password = json['response'] if password.nil? && json['response'].is_a?(String)
      expect(password).to eq('generated-password')
      expect(seen[:type]).to eq('secure')
    end

    it 'accepts explicit type' do
      seen = {}
      allow(VpsAdmin::API::Operations::Vps::Passwd).to receive(:run) do |_target, type|
        seen[:type] = type
        [fake_chain!(TransactionChains::Vps::Passwd), 'simple-password']
      end

      as(SpecSeed.user) { json_post passwd_path(vps.id), vps: { type: 'simple' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(seen[:type]).to eq('simple')
    end
  end

  describe 'Boot' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post boot_path(vps.id), vps: { mount_root_dataset: '/rootfs' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post boot_path(vps.id), vps: { mount_root_dataset: '/rootfs' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'rejects non-vpsadminos nodes' do
      node = create_node!(
        name_prefix: 'spec-openvz',
        location: SpecSeed.location,
        role: :node,
        hypervisor_type: :openvz,
        total_swap: 512
      )
      other_vps = create_vps!(user: SpecSeed.user, node: node)

      as(SpecSeed.user) { json_post boot_path(other_vps.id), vps: { mount_root_dataset: '/rootfs' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('available only for VPS running on vpsAdminOS')
    end

    it 'rejects invalid mount_root_dataset' do
      as(SpecSeed.user) { json_post boot_path(vps.id), vps: { mount_root_dataset: '../bad' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('mount_root_dataset')
    end

    it 'rejects disabled templates' do
      disabled = create_os_template!(hypervisor_type: :vpsadminos, enabled: false)

      as(SpecSeed.user) { json_post boot_path(vps.id), vps: { os_template: disabled.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('disabled')
    end

    it 'rejects incompatible templates' do
      mismatch = create_os_template!(hypervisor_type: :openvz, enabled: true)

      as(SpecSeed.user) { json_post boot_path(vps.id), vps: { os_template: mismatch.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('incompatible template')
    end

    it 'boots VPS with valid params' do
      allow(TransactionChains::Vps::Boot).to receive(:fire) do |_target, _tpl, **_kwargs|
        [fake_chain!(TransactionChains::Vps::Boot), nil]
      end

      expect do
        as(SpecSeed.user) do
          json_post boot_path(vps.id), vps: { mount_root_dataset: '/rootfs' }
        end
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Reinstall' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post reinstall_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post reinstall_path(vps.id), vps: {} }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'defaults os_template when omitted' do
      seen = {}
      allow(VpsAdmin::API::Operations::Vps::Reinstall).to receive(:run) do |_target, input|
        seen[:os_template] = input[:os_template]
        fake_chain!(TransactionChains::Vps::Reinstall)
      end

      as(SpecSeed.user) { json_post reinstall_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(seen[:os_template]).to eq(vps.os_template)
    end

    it 'surfaces operation errors' do
      allow(VpsAdmin::API::Operations::Vps::Reinstall).to receive(:run)
        .and_raise(VpsAdmin::API::Exceptions::OperationError.new('boom'))

      as(SpecSeed.user) { json_post reinstall_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('boom')
    end
  end

  describe 'Migrate' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }
    let(:target_node) do
      create_node!(
        name_prefix: 'spec-migrate',
        location: SpecSeed.location,
        role: :node,
        hypervisor_type: :vpsadminos
      )
    end

    it 'rejects unauthenticated access' do
      json_post migrate_path(vps.id), vps: { node: target_node.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post migrate_path(vps.id), vps: { node: target_node.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post migrate_path(vps.id), vps: { node: target_node.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'rejects migrating to the same node' do
      as(SpecSeed.admin) { json_post migrate_path(vps.id), vps: { node: SpecSeed.node.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('already is on this very node')
    end

    it 'rejects non-hypervisor nodes' do
      storage = create_node!(
        name_prefix: 'spec-storage',
        location: SpecSeed.location,
        role: :storage,
        hypervisor_type: :vpsadminos
      )

      as(SpecSeed.admin) { json_post migrate_path(vps.id), vps: { node: storage.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('target node is not a hypervisor')
    end

    it 'requires finish_weekday and finish_minutes together' do
      as(SpecSeed.admin) do
        json_post migrate_path(vps.id), vps: { node: target_node.id, finish_weekday: 1 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('finish_weekday', 'finish_minutes')
    end

    it 'rejects finish config with maintenance_window' do
      as(SpecSeed.admin) do
        json_post migrate_path(vps.id), vps: {
          node: target_node.id,
          finish_weekday: 1,
          finish_minutes: 60,
          maintenance_window: true
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('maintenance_window')
    end

    it 'migrates for admin' do
      allow(VpsAdmin::API::Operations::Vps::Migrate).to receive(:run) do |_target, _input|
        fake_chain!(TransactionChains::Vps::Migrate::Base)
      end

      as(SpecSeed.admin) { json_post migrate_path(vps.id), vps: { node: target_node.id } }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Clone' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-src') }
    let(:destination_node) do
      create_node!(
        name_prefix: 'spec-clone',
        location: SpecSeed.location,
        role: :node,
        hypervisor_type: :vpsadminos
      )
    end

    before do
      allow(VpsAdmin::API::Operations::Node::Pick).to receive(:run).and_return(destination_node)
    end

    it 'rejects unauthenticated access' do
      json_post clone_path(vps.id), vps: { environment: SpecSeed.environment.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) do
        json_post clone_path(vps.id), vps: { environment: SpecSeed.environment.id }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'requires environment, location or node' do
      as(SpecSeed.user) { json_post clone_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('provide environment, location or node')
    end

    it 'clones VPS for owner with picked node' do
      set_env_config!(
        user: SpecSeed.user,
        environment: SpecSeed.environment,
        attrs: { can_create_vps: true, max_vps_count: 10 }
      )

      allow(TransactionChains::Vps::Clone).to receive(:chain_for) do |_src, _dst|
        class_double(TransactionChains::Vps::Clone::OsToOs).tap do |chain|
          allow(chain).to receive(:fire) do |_src_vps, node, input|
            cloned = create_vps!(user: input[:user], node: node, hostname: input[:hostname])
            [fake_chain!(TransactionChains::Vps::Clone::OsToOs), cloned]
          end
        end
      end

      expect do
        as(SpecSeed.user) { json_post clone_path(vps.id), vps: { environment: SpecSeed.environment.id } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      cloned_id = vps_obj['id']
      expect(Vps.where(id: cloned_id)).to exist
      expect(Vps.find(cloned_id).user_id).to eq(SpecSeed.user.id)
    end

    it 'sets default hostname when missing' do
      set_env_config!(
        user: SpecSeed.user,
        environment: SpecSeed.environment,
        attrs: { can_create_vps: true, max_vps_count: 10 }
      )

      seen = {}
      allow(TransactionChains::Vps::Clone).to receive(:chain_for) do |_src, _dst|
        class_double(TransactionChains::Vps::Clone::OsToOs).tap do |chain|
          allow(chain).to receive(:fire) do |_src_vps, node, input|
            seen[:hostname] = input[:hostname]
            cloned = create_vps!(user: input[:user], node: node, hostname: input[:hostname])
            [fake_chain!(TransactionChains::Vps::Clone::OsToOs), cloned]
          end
        end
      end

      as(SpecSeed.user) { json_post clone_path(vps.id), vps: { environment: SpecSeed.environment.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(seen[:hostname]).to eq("#{vps.hostname}-#{vps.id}-clone")
    end

    it 'allows admin to clone to explicit node' do
      allow(TransactionChains::Vps::Clone).to receive(:chain_for).with(vps, destination_node) do
        class_double(TransactionChains::Vps::Clone::OsToOs).tap do |chain|
          allow(chain).to receive(:fire) do |_src_vps, node, input|
            cloned = create_vps!(user: input[:user], node: node, hostname: input[:hostname])
            [fake_chain!(TransactionChains::Vps::Clone::OsToOs), cloned]
          end
        end
      end

      as(SpecSeed.admin) { json_post clone_path(vps.id), vps: { node: destination_node.id } }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'SwapWith' do
    it 'rejects unauthenticated access' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      other_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.other_node)

      json_post swap_with_path(vps.id), vps: { vps: other_vps.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      other_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.other_node)

      as(SpecSeed.other_user) { json_post swap_with_path(vps.id), vps: { vps: other_vps.id } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'rejects swapping across different owners' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      other_vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node)

      as(SpecSeed.user) { json_post swap_with_path(vps.id), vps: { vps: other_vps.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'rejects swap within one location' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-swap-a')
      other_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-swap-b')

      as(SpecSeed.user) { json_post swap_with_path(vps.id), vps: { vps: other_vps.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('swap within one location is not needed')
    end

    it 'swaps VPSes across locations' do
      vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node)
      other_vps = create_vps!(user: SpecSeed.user, node: SpecSeed.other_node)

      allow(TransactionChains::Vps::Swap).to receive(:fire) do |_src, _dst, _input|
        [fake_chain!(TransactionChains::Vps::Swap), nil]
      end

      expect do
        as(SpecSeed.user) { json_post swap_with_path(vps.id), vps: { vps: other_vps.id } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end

  describe 'Replace' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }

    it 'rejects unauthenticated access' do
      json_post replace_path(vps.id), vps: {}

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post replace_path(vps.id), vps: {} }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to replace VPS' do
      allow(TransactionChains::Vps::Replace).to receive(:chain_for) do |_src, _dst|
        class_double(TransactionChains::Vps::Replace::Os).tap do |chain|
          allow(chain).to receive(:fire) do |_src_vps, node, _input|
            replaced = create_vps!(user: vps.user, node: node, hostname: "spec-replace-#{SecureRandom.hex(4)}")
            [fake_chain!(TransactionChains::Vps::Replace::Os), replaced]
          end
        end
      end

      as(SpecSeed.admin) { json_post replace_path(vps.id), vps: {} }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(Vps.where(id: vps_obj['id'])).to exist
    end
  end

  describe 'DeployPublicKey' do
    let!(:vps) { create_vps!(user: SpecSeed.user, node: SpecSeed.node) }
    let!(:key) { create_public_key!(user: SpecSeed.user) }

    it 'rejects unauthenticated access' do
      json_post deploy_public_key_path(vps.id), vps: { public_key: key.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'hides VPS from other users' do
      as(SpecSeed.other_user) { json_post deploy_public_key_path(vps.id), vps: { public_key: key.id } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'deploys public key for owner' do
      allow(TransactionChains::Vps::DeployPublicKey).to receive(:fire) do |_target, _key|
        [fake_chain!(TransactionChains::Vps::DeployPublicKey), nil]
      end

      expect do
        as(SpecSeed.user) { json_post deploy_public_key_path(vps.id), vps: { public_key: key.id } }
      end.to change(TransactionChain, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
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
    return SpecSeed.pool if node.id == SpecSeed.node.id
    return SpecSeed.other_pool if node.id == SpecSeed.other_node.id

    Pool.find_by(node: node) || create_pool!(node: node)
  end

  def create_pool!(node:, label: nil)
    suffix = SecureRandom.hex(4)

    pool = Pool.new(
      node: node,
      label: label || "Spec Pool #{suffix}",
      filesystem: "spec_pool_#{suffix}",
      role: :hypervisor
    )
    pool.save!
    pool
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
                  dns_resolver: SpecSeed.dns_resolver, dataset_in_pool: nil, user_namespace_map: nil)
    dataset_in_pool ||= create_dataset_in_pool!(pool: pool_for_node(node), user: user)

    vps = Vps.new(
      user: user,
      node: node,
      hostname: hostname || "spec-vps-#{SecureRandom.hex(4)}",
      os_template: os_template,
      dns_resolver: dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active,
      confirmed: :confirmed,
      user_namespace_map: user_namespace_map
    )

    with_current_user(SpecSeed.admin) do
      vps.save!
    end

    vps
  rescue ActiveRecord::RecordInvalid
    vps.save!(validate: false)
    vps
  end

  def create_node!(name_prefix:, location:, role: :node, hypervisor_type: :vpsadminos, total_swap: 512)
    suffix = SecureRandom.hex(3)

    Node.create!(
      name: "#{name_prefix}-#{suffix}",
      location: location,
      role: role,
      hypervisor_type: hypervisor_type,
      ip_addr: random_ipv4,
      max_vps: role == :node ? 10 : nil,
      cpus: 2,
      total_memory: 2048,
      total_swap: total_swap,
      active: true
    )
  end

  def create_os_template!(hypervisor_type:, enabled: true, cgroup_version: :cgroup_any)
    suffix = SecureRandom.hex(4)

    OsTemplate.create!(
      os_family: SpecSeed.os_family,
      label: "Spec Template #{suffix}",
      distribution: 'specos',
      version: '1',
      arch: 'x86_64',
      vendor: 'spec',
      variant: 'base',
      hypervisor_type: hypervisor_type,
      cgroup_version: cgroup_version,
      enabled: enabled,
      config: {}
    )
  end

  def create_dns_resolver!(is_universal:, location: nil, ip_version: 4)
    suffix = SecureRandom.hex(4)

    DnsResolver.create!(
      addrs: "192.0.2.#{100 + SecureRandom.random_number(80)}",
      label: "Spec DNS #{suffix}",
      is_universal: is_universal,
      location: location,
      ip_version: ip_version
    )
  end

  def create_public_key!(user:)
    UserPublicKey.create!(
      user: user,
      label: 'Spec Key',
      key: 'ssh-ed25519 aGVsbG8= spec@test',
      auto_add: false
    )
  end

  def set_env_config!(user:, environment:, attrs:)
    config = EnvironmentUserConfig.find_by!(user: user, environment: environment)
    config.update!(attrs)
    config
  end

  def ensure_user_cluster_resource!(user:, environment:, resource:, value: 10_000)
    cluster_resource = ClusterResource.find_by!(name: resource.to_s)
    record = UserClusterResource.find_or_initialize_by(
      user: user,
      environment: environment,
      cluster_resource: cluster_resource
    )
    record.value = value if record.new_record? || record.value.to_i < value
    record.save! if record.changed?
    record
  end

  def allocate_vps_resource!(vps, resource, value)
    ensure_user_cluster_resource!(
      user: vps.user,
      environment: vps.node.location.environment,
      resource: resource
    )
    vps.reallocate_resource!(
      resource,
      value,
      user: vps.user,
      save: true,
      confirmed: ::ClusterResourceUse.confirmed(:confirmed)
    )
  end
end
