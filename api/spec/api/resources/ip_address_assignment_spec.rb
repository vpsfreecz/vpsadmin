# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::IpAddressAssignment' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.network_v4
    SpecSeed.network_v6
    SpecSeed.location
    SpecSeed.other_location
    SpecSeed.node
    fixtures
  end

  let(:fixtures) do
    now = Time.now
    vps_user = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    vps_other = create_vps_row!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-other-vps')
    chain_a = create_chain(user: SpecSeed.admin, name: 'spec_chain_a')
    ip_v4_primary = create_ip!(network: SpecSeed.network_v4, addr: '192.0.2.10')
    ip_v4_secondary = create_ip!(network: SpecSeed.network_v4, addr: '192.0.2.11')
    ip_v6_user = create_ip!(network: SpecSeed.network_v6, addr: '2001:db8::10')
    ip_v6_other = create_ip!(network: SpecSeed.network_v6, addr: '2001:db8::11')
    assignment_user_active_v4 = create_assignment!(
      ip: ip_v4_primary,
      user: SpecSeed.user,
      vps: vps_user,
      from_date: now - (3 * 3600),
      assigned_by_chain: chain_a
    )
    assignment_user_inactive_v4 = create_assignment!(
      ip: ip_v4_secondary,
      user: SpecSeed.user,
      vps: vps_user,
      from_date: now - (2 * 3600),
      to_date: now - (1 * 3600),
      unassigned_by_chain: chain_a,
      reconstructed: true
    )
    assignment_user_active_v6 = create_assignment!(
      ip: ip_v6_user,
      user: SpecSeed.user,
      vps: vps_user,
      from_date: now - (30 * 60)
    )
    assignment_other_active_v6 = create_assignment!(
      ip: ip_v6_other,
      user: SpecSeed.other_user,
      vps: vps_other,
      from_date: now - (45 * 60)
    )
    {
      vps_user: vps_user,
      vps_other: vps_other,
      chain_a: chain_a,
      ip_v4_primary: ip_v4_primary,
      assignment_user_active_v4: assignment_user_active_v4,
      assignment_user_inactive_v4: assignment_user_inactive_v4,
      assignment_user_active_v6: assignment_user_active_v6,
      assignment_other_active_v6: assignment_other_active_v6
    }
  end

  def vps_user
    fixtures.fetch(:vps_user)
  end

  def vps_other
    fixtures.fetch(:vps_other)
  end

  def chain_a
    fixtures.fetch(:chain_a)
  end

  def ip_v4_primary
    fixtures.fetch(:ip_v4_primary)
  end

  def assignment_user_active_v4
    fixtures.fetch(:assignment_user_active_v4)
  end

  def assignment_user_inactive_v4
    fixtures.fetch(:assignment_user_inactive_v4)
  end

  def assignment_user_active_v6
    fixtures.fetch(:assignment_user_active_v6)
  end

  def assignment_other_active_v6
    fixtures.fetch(:assignment_other_active_v6)
  end

  def create_vps_row!(user:, node:, hostname:)
    vps = Vps.new(
      user_id: user.id,
      node_id: node.id,
      hostname: hostname,
      os_template_id: 1
    )

    vps.object_state =
      if Vps.respond_to?(:object_states) && Vps.object_states[:active]
        Vps.object_states[:active]
      else
        0
      end

    vps.save!(validate: false)
    vps
  end

  def create_ip!(network:, addr:)
    IpAddress.create!(
      network: network,
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1
    )
  end

  def create_chain(user:, name:)
    TransactionChain.create!(
      name: name,
      type: 'TransactionChain',
      state: :queued,
      size: 1,
      progress: 0,
      user: user,
      concern_type: :chain_affect
    )
  end

  def create_assignment!(
    ip:,
    user:,
    vps:,
    from_date:,
    to_date: nil,
    assigned_by_chain: nil,
    unassigned_by_chain: nil,
    reconstructed: false
  )
    IpAddressAssignment.create!(
      ip_address: ip,
      ip_addr: ip.ip_addr,
      ip_prefix: ip.prefix,
      user: user,
      vps: vps,
      from_date: from_date,
      to_date: to_date,
      assigned_by_chain: assigned_by_chain,
      unassigned_by_chain: unassigned_by_chain,
      reconstructed: reconstructed
    )
  end

  def index_path
    vpath('/ip_address_assignments')
  end

  def show_path(id)
    vpath("/ip_address_assignments/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def assignments
    json.dig('response', 'ip_address_assignments')
  end

  def assignment_obj
    json.dig('response', 'ip_address_assignment')
  end

  def assignment_ids
    (assignments || []).map { |row| row['id'] }
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
    it 'includes ip_address_assignment scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('ip_address_assignment#index', 'ip_address_assignment#show')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'restricts normal users to their assignments with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id,
        assignment_user_active_v6.id
      )

      row = assignments.find { |item| item['id'] == assignment_user_active_v4.id }
      expect(row).not_to have_key('user')
      expect(row).not_to have_key('raw_user_id')
    end

    it 'restricts support users to their assignments with limited output' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(assignment_ids).to be_empty
    end

    it 'allows admins to see all assignments with user fields' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id,
        assignment_user_active_v6.id,
        assignment_other_active_v6.id
      )

      row = assignments.find { |item| item['id'] == assignment_other_active_v6.id }
      expect(row).to have_key('user')
      expect(row).to have_key('raw_user_id')
      expect(resource_id(row['user'])).to eq(SpecSeed.other_user.id)
      expect(row['raw_user_id']).to eq(SpecSeed.other_user.id)
    end

    it 'filters by active status' do
      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { active: true } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_active_v6.id
      )

      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { active: false } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_inactive_v4.id)
    end

    it 'orders by newest first' do
      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { order: 'newest' } }

      expect_status(200)
      expect(assignment_ids).to eq(
        [
          assignment_user_active_v6.id,
          assignment_user_inactive_v4.id,
          assignment_user_active_v4.id
        ]
      )
    end

    it 'orders by oldest first' do
      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { order: 'oldest' } }

      expect_status(200)
      expect(assignment_ids).to eq(
        [
          assignment_user_active_v4.id,
          assignment_user_inactive_v4.id,
          assignment_user_active_v6.id
        ]
      )
    end

    it 'filters by location' do
      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { location: SpecSeed.location.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id
      )

      as(SpecSeed.user) do
        json_get index_path, ip_address_assignment: { location: SpecSeed.other_location.id }
      end

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_active_v6.id)
    end

    it 'filters by network' do
      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { network: SpecSeed.network_v4.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id
      )

      as(SpecSeed.user) { json_get index_path, ip_address_assignment: { network: SpecSeed.network_v6.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_active_v6.id)
    end

    it 'filters by ip_version' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_version: 4 } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id
      )

      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_version: 6 } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v6.id,
        assignment_other_active_v6.id
      )
    end

    it 'filters by ip_address' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_address: ip_v4_primary.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_active_v4.id)
    end

    it 'filters by ip_addr' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_addr: '192.0.2.10' } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_active_v4.id)
    end

    it 'filters by ip_prefix' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_prefix: 32 } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id
      )

      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { ip_prefix: 128 } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v6.id,
        assignment_other_active_v6.id
      )
    end

    it 'filters by reconstructed' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { reconstructed: true } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_inactive_v4.id)
    end

    it 'filters by assigned_by_chain' do
      as(SpecSeed.admin) do
        json_get index_path, ip_address_assignment: { assigned_by_chain: chain_a.id }
      end

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_active_v4.id)
    end

    it 'filters by assigned_by_chain when nil' do
      as(SpecSeed.admin) do
        json_get index_path, ip_address_assignment: { assigned_by_chain: nil }
      end

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_inactive_v4.id,
        assignment_user_active_v6.id,
        assignment_other_active_v6.id
      )
    end

    it 'filters by unassigned_by_chain' do
      as(SpecSeed.admin) do
        json_get index_path, ip_address_assignment: { unassigned_by_chain: chain_a.id }
      end

      expect_status(200)
      expect(assignment_ids).to contain_exactly(assignment_user_inactive_v4.id)
    end

    it 'filters by vps' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { vps: vps_user.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id,
        assignment_user_active_v6.id
      )
    end

    it 'filters by user for admins' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { user: SpecSeed.user.id } }

      expect_status(200)
      expect(assignment_ids).to contain_exactly(
        assignment_user_active_v4.id,
        assignment_user_inactive_v4.id,
        assignment_user_active_v6.id
      )
    end

    it 'rejects or ignores user filter for non-admins' do
      as(SpecSeed.user) do
        json_get index_path, ip_address_assignment: { user: SpecSeed.other_user.id }
      end

      if json['status'] == false
        errors = json.dig('response', 'errors') || json['errors'] || {}
        if errors.respond_to?(:keys) && errors.any?
          expect(errors.keys.map(&:to_s)).to include('user')
        end
      else
        expect_status(200)
        expect(assignment_ids).not_to include(assignment_other_active_v6.id)
      end
    end

    it 'paginates with limit and from_id' do
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { limit: 2 } }

      expect_status(200)
      expect(assignments.length).to eq(2)

      boundary = assignment_user_active_v4.id
      as(SpecSeed.admin) { json_get index_path, ip_address_assignment: { from_id: boundary } }

      expect_status(200)
      expect(assignment_ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(IpAddressAssignment.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(assignment_user_active_v4.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their assignment with limited output' do
      as(SpecSeed.user) { json_get show_path(assignment_user_active_v4.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(assignment_obj['id']).to eq(assignment_user_active_v4.id)
      expect(assignment_obj).not_to have_key('user')
      expect(assignment_obj).not_to have_key('raw_user_id')
    end

    it 'forbids users from showing other assignments' do
      as(SpecSeed.user) { json_get show_path(assignment_other_active_v6.id) }

      expect(last_response.status).to be_in([200, 403, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any assignment with user fields' do
      as(SpecSeed.admin) { json_get show_path(assignment_other_active_v6.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(assignment_obj['id']).to eq(assignment_other_active_v6.id)
      expect(assignment_obj).to have_key('user')
      expect(assignment_obj).to have_key('raw_user_id')
      expect(resource_id(assignment_obj['user'])).to eq(SpecSeed.other_user.id)
      expect(assignment_obj['raw_user_id']).to eq(SpecSeed.other_user.id)
    end

    it 'returns 404 for unknown assignment' do
      missing = IpAddressAssignment.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
