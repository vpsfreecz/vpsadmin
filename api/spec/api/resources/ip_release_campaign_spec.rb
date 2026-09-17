require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::IpReleaseCampaign do
  before do
    header 'Accept', 'application/json'
    ensure_signer_unlocked!
    ensure_available_node_status!(SpecSeed.node)
  end

  def create_fixture(user: SpecSeed.user)
    with_current_context do
      ip = create_ip_address!(user:)
      ip.update!(charged_environment: SpecSeed.environment)
      campaign = IpReleaseCampaign.create_selected!(ids: [ip.id], actor: SpecSeed.admin,
                                                    deadline: Time.now + 604_800)
      [campaign, campaign.ip_release_requests.first, campaign.ip_release_request_addresses.first, ip]
    end
  end

  def read(path, params = {})
    get vpath(path), params, 'CONTENT_TYPE' => 'application/json', 'rack.input' => StringIO.new('{}')
  end

  def write(path, payload = {})
    post vpath(path), JSON.dump(payload), 'CONTENT_TYPE' => 'application/json'
  end

  def expect_status(status)
    expect(last_response.status).to eq(status), last_response.body
  end

  it 'returns one shared attempt and restricts its history to administrators and its campaign' do
    c, = create_fixture
    foreign, = create_fixture(user: SpecSeed.other_user)
    as(SpecSeed.admin) do
      write("/ip_release_campaigns/#{c.id}/release")
      expect_status(200)
      response = JSON.parse(last_response.body)
      expect(response.fetch('status')).to be(true)
      attempt = c.latest_release_attempt
      expect(last_response.body).to include('transaction_chain', 'running')
      expect(attempt.ip_count).to eq(1)
      write("/ip_release_campaigns/#{c.id}/release")
      expect_status(200)
      expect(c.ip_release_attempts.count).to eq(1)
      read("/ip_release_campaigns/#{c.id}/attempts")
      expect_status(200)
      expect(last_response.body).to include('created_by_id', 'ip_count')
      read("/ip_release_campaigns/#{c.id}/attempts/#{attempt.id}")
      expect_status(200)
      read("/ip_release_campaigns/#{c.id}")
      expect_status(200)
      association = JSON.parse(last_response.body).fetch('response').fetch('ip_release_campaign')
                        .fetch('latest_release_attempt')
      ids = association.fetch('_meta').fetch('path_params')
      expect(ids).to eq([c.id, attempt.id])
      read("/ip_release_campaigns/#{ids.first}/attempts/#{ids.last}")
      expect_status(200)
      read("/ip_release_campaigns/#{foreign.id}/attempts/#{attempt.id}")
      expect_status(404)
    end
    [SpecSeed.user, SpecSeed.other_user, SpecSeed.support].each do |user|
      as(user) do
        read("/ip_release_campaigns/#{c.id}/attempts")
        expect_status(403)
        read("/ip_release_campaigns/#{c.id}/attempts/#{c.latest_release_attempt.id}")
        expect_status(403)
      end
    end
  end

  it "returns another administrator's running attempt without an inaccessible action state" do
    c, = create_fixture
    as(SpecSeed.admin) { write("/ip_release_campaigns/#{c.id}/release") }
    attempt = c.latest_release_attempt
    SpecSeed.other_user.update!(level: 99)
    as(SpecSeed.other_user) do
      write("/ip_release_campaigns/#{c.id}/release")
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      expect(last_response.body).to include('transaction_chain', 'running')
    end
    expect(c.latest_release_attempt.id).to eq(attempt.id)
  end

  it 'lists campaign addresses across owners and records only the authenticated exemption actor' do
    campaign = with_current_context do
      ips = [SpecSeed.user, SpecSeed.other_user].map { |user| create_ip_address!(user:) }
      IpReleaseCampaign.create_selected!(ids: ips.map(&:id), actor: SpecSeed.admin, deadline: Time.now)
    end
    ids = campaign.ip_release_request_addresses.order(:id).pluck(:id)
    as(SpecSeed.admin) do
      read("/ip_release_campaigns/#{campaign.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include(SpecSeed.user.login, SpecSeed.other_user.login, 'location_label')
      read("/ip_release_campaigns/#{campaign.id}/addresses", address: { limit: 1, from_id: ids.first })
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('response').fetch('addresses').map { |row| row.fetch('id') }).to eq([ids.last])
      write("/ip_release_campaigns/#{campaign.id}/exempt", ip_release_campaign: { addresses: ids, reason: 'Reservation' })
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      read("/ip_release_campaigns/#{campaign.id}/addresses")
      expect(last_response.body).to include('exempted_by_id', SpecSeed.admin.login)
    end
    expect(campaign.ip_release_request_addresses.pluck(:exempted_by_id).uniq).to eq([SpecSeed.admin.id])
    request = campaign.ip_release_requests.find_by!(user: SpecSeed.user)
    as(SpecSeed.user) do
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include('Reservation')
      expect(last_response.body).not_to include('exempted_by', 'kept_by', SpecSeed.other_user.login, SpecSeed.admin.login)
    end
  end

  it 'retains raw actor IDs when the actor no longer exists' do
    campaign, request, entry = create_fixture
    entry.update!(keep_reason: 'Old reason', kept_at: Time.now, kept_by_id: 2_000_000_001,
                  exemption_reason: 'Old exemption', exempted_at: Time.now, exempted_by_id: 2_000_000_002)
    as(SpecSeed.admin) do
      read("/ip_release_campaigns/#{campaign.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include('2000000001', '2000000002')
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include('2000000001', '2000000002')
    end
  end

  it 'requires a reason to set exemptions and an explicit flag to remove them' do
    campaign, _request, item = create_fixture
    with_current_context { item.exempt!(reason: 'Reservation', actor: SpecSeed.admin) }
    as(SpecSeed.admin) do
      [{}, { reason: nil }, { reason: '' }, { reason: ' ' }, { remove: false }].each do |params|
        write("/ip_release_campaigns/#{campaign.id}/exempt", ip_release_campaign: params.merge(addresses: [item.id]))
        expect(JSON.parse(last_response.body).fetch('status')).to be(false)
        expect(item.reload.exemption_reason).to eq('Reservation')
      end
      write("/ip_release_campaigns/#{campaign.id}/exempt", ip_release_campaign: { addresses: [item.id], remove: true })
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      expect(item.reload.exempted_at).to be_nil
      expect(item.exempted_by_id).to be_nil
      expect(item.exemption_reason).to be_nil
    end
  end

  it 'lets an admin preview and create a campaign with seven-day and opt-out defaults' do
    ip = with_current_context { create_ip_address!(user: SpecSeed.user) }
    as(SpecSeed.admin) do
      read('/ip_release_campaigns/candidates')
      expect_status(200)
      expect(last_response.body).to include(ip.addr)
      read('/ip_release_campaigns/candidates', ip_release_campaign: { limit: 500, versions: '4,6', networks: ip.network_id.to_s, locations: SpecSeed.location.id.to_s, access: 'all', user: ip.user_id })
      expect_status(200)
      expect(last_response.body).to include(ip.addr)
      write('/ip_release_campaigns', ip_release_campaign: { addresses: [ip.id] })
      expect_status(200)
    end
    c = IpReleaseCampaign.last
    expect(c.allow_keep).to be(true)
    expect(c.deadline).to be_within(10).of(Time.now + 604_800)
  end

  it 'paginates candidate selections' do
    ips = with_current_context { Array.new(2) { create_ip_address!(user: SpecSeed.user) } }
    as(SpecSeed.admin) do
      read('/ip_release_campaigns/candidates', ip_release_campaign: { limit: 1, from_id: ips.first.id - 1 })
      expect_status(200)
      expect(last_response.body).to include(ips.first.addr)
      expect(last_response.body).not_to include(ips.last.addr)
      read('/ip_release_campaigns/candidates', ip_release_campaign: { limit: 1, from_id: ips.first.id })
      expect_status(200)
      expect(last_response.body).to include(ips.last.addr)
    end
    expect(IpReleaseCampaign.count).to eq(0)
  end

  it 'shows notice history only to administrators' do
    c, request = create_fixture
    with_current_context do
      ensure_available_node_status!(SpecSeed.node)
      ensure_user_mail_templates!
      c.notify!(event: 'requested', actor: SpecSeed.admin)
      c.notify!(event: 'reminder', actor: SpecSeed.admin)
    end
    [SpecSeed.user, SpecSeed.other_user, SpecSeed.support].each do |user|
      as(user) do
        read("/ip_release_requests/#{request.id}/notices")
        expect_status(403)
        read("/ip_release_campaigns/#{c.id}/notices")
        expect_status(403)
      end
    end
    as(SpecSeed.admin) do
      read("/ip_release_requests/#{request.id}/notices")
      expect_status(200)
      expect(last_response.body).to include('mail_log', 'created_by')
      read("/ip_release_campaigns/#{c.id}/notices")
      expect_status(200)
      expect(last_response.body).to include('requested', 'reminder', SpecSeed.user.login)
    end
  end

  it 'shows deleted-owner history without resolving an unavailable user resource' do
    c, request, entry, ip = create_fixture
    SpecSeed.user.update!(object_state: 'hard_delete')
    as(SpecSeed.admin) do
      read("/ip_release_requests/#{request.id}")
      expect_status(200)
      expect(last_response.body).to include('original_user_id')
      read('/ip_release_requests', ip_release_request: { ip_release_campaign: c.id })
      expect_status(200)
      write("/ip_release_campaigns/#{c.id}/release")
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include('owner_deleted')
    end
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(entry.reload.excluded_at).not_to be_nil
  end

  it 'lets an admin inspect, notify, exempt and close a campaign without releasing its address' do
    campaign, request, item, ip = create_fixture
    with_current_context do
      ensure_available_node_status!(SpecSeed.node)
      ensure_user_mail_templates!
    end
    as(SpecSeed.admin) do
      read('/ip_release_campaigns', ip_release_campaign: { limit: 500 })
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      expect(last_response.body).to include('deadline', 'allow_keep')
      read("/ip_release_campaigns/#{campaign.id}")
      expect_status(200)
      expect(last_response.body).to include('deadline', 'allow_keep')
      write("/ip_release_campaigns/#{campaign.id}/notify", ip_release_campaign: { event: 'requested' })
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      expect(request.ip_release_request_notices.count).to eq(1)
      write("/ip_release_requests/#{request.id}/addresses/#{item.id}/exempt", address: { reason: 'Reservation' })
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      expect(item.reload.exemption_reason).to eq('Reservation')
      write("/ip_release_campaigns/#{campaign.id}/close")
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
    end
    expect(campaign.reload.closed_at).not_to be_nil
    expect(item.reload.active_ip_address_id).to be_nil
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    as(SpecSeed.user) do
      read("/ip_release_requests/#{request.id}")
      expect_status(200)
      response = JSON.parse(last_response.body).fetch('response').fetch('ip_release_request')
      expect(response.values_at('can_keep', 'can_assign')).to eq([false, false])
      write("/ip_release_requests/#{request.id}/keep", ip_release_request: { addresses: [item.id], reason: 'Too late' })
      expect(JSON.parse(last_response.body).fetch('status')).to be(false)
    end
    expect(item.reload.kept_at).to be_nil
    as(SpecSeed.admin) do
      write("/ip_release_requests/#{request.id}/addresses/#{item.id}/exempt", address: { reason: nil })
      expect(JSON.parse(last_response.body).fetch('status')).to be(false)
      write("/ip_release_campaigns/#{campaign.id}/exempt", ip_release_campaign: { addresses: [item.id], reason: 'Too late' })
      expect(JSON.parse(last_response.body).fetch('status')).to be(false)
    end
    expect(item.reload.exemption_reason).to eq('Reservation')
  end

  it 'denies campaign management to ordinary users and support staff' do
    c, request, item = create_fixture
    [SpecSeed.user, SpecSeed.support].each do |user|
      as(user) do
        read('/ip_release_campaigns')
        expect_status(403)
        read('/ip_release_campaigns/candidates')
        expect_status(403)
        read("/ip_release_campaigns/#{c.id}/addresses")
        expect_status(403)
        read("/ip_release_campaigns/#{c.id}/notices")
        expect_status(403)
        %w[release close notify exempt].each do |action|
          write("/ip_release_campaigns/#{c.id}/#{action}")
          expect_status(403)
        end
        write("/ip_release_requests/#{request.id}/addresses/#{item.id}/exempt", address: { reason: 'Keep' })
        expect_status(403)
      end
    end
  end

  it 'scopes request lists, details and nested addresses to the owner' do
    _c, request, item, ip = create_fixture
    as(SpecSeed.other_user) do
      read('/ip_release_requests')
      expect_status(200)
      expect(last_response.body).not_to include(ip.addr)
      read("/ip_release_requests/#{request.id}")
      expect_status(404)
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(404)
      read("/ip_release_requests/#{request.id}/notices")
      expect_status(403)
      write("/ip_release_requests/#{request.id}/keep", ip_release_request: { addresses: [item.id], reason: 'Keep' })
      expect_status(404)
    end
    as(SpecSeed.user) do
      read("/ip_release_requests/#{request.id}")
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('status')).to be(true)
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      expect(last_response.body).to include(ip.addr)
    end
  end

  it 'accepts reasons after the advisory deadline and ignores them only under forced policy' do
    c, request, item, ip = create_fixture
    c.edit!({ deadline: Time.now - 60 }, actor: SpecSeed.admin)
    as(SpecSeed.user) do
      write("/ip_release_requests/#{request.id}/keep", ip_release_request: { addresses: [item.id], reason: 'Migration' })
      expect_status(200)
    end
    as(SpecSeed.admin) do
      write("/ip_release_campaigns/#{c.id}/release")
      expect_status(200)
      expect(ip.reload.user_id).to eq(SpecSeed.user.id)
      put vpath("/ip_release_campaigns/#{c.id}"), JSON.dump(ip_release_campaign: { allow_keep: false }),
          'CONTENT_TYPE' => 'application/json'
      expect_status(200)
      write("/ip_release_campaigns/#{c.id}/release")
      expect_status(200)
    end
    expect(ip.reload.user_id).to eq(SpecSeed.user.id)
    expect(c.latest_release_attempt.state).to eq('running')
    expect(item.reload.keep_reason).to eq('Migration')
  end

  it 'rejects nested exemption IDs from another request' do
    _c, request = create_fixture
    _other_c, _other_request, other_item = create_fixture(user: SpecSeed.other_user)
    as(SpecSeed.admin) do
      write("/ip_release_requests/#{request.id}/addresses/#{other_item.id}/exempt", address: { reason: 'Keep' })
      expect_status(404)
    end
    expect(other_item.reload.exempted_at).to be_nil
  end

  it 'returns only member fields from request, address and keep responses' do
    _campaign, request, item, ip = create_fixture
    as(SpecSeed.user) do
      read('/ip_release_requests', ip_release_request: { limit: 500 })
      expect_status(200)
      rows = JSON.parse(last_response.body).fetch('response').fetch('ip_release_requests')
      expect(rows.first.except('_meta').keys).to match_array(%w[id deadline can_keep can_assign])
      read("/ip_release_requests/#{request.id}")
      expect_status(200)
      response = JSON.parse(last_response.body).fetch('response').fetch('ip_release_request')
      expect(response.keys).to match_array(%w[id deadline can_keep can_assign])
      write("/ip_release_requests/#{request.id}/keep", ip_release_request: { addresses: [item.id], reason: 'Migration' })
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('response').fetch('ip_release_request').keys)
        .to match_array(%w[id deadline can_keep can_assign])
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      response = JSON.parse(last_response.body).fetch('response').fetch('addresses').first
      expect(response.except('_meta').keys).to match_array(described_class::AddressParams::MEMBER_FIELDS.map(&:to_s))
      expect(response.fetch('_meta').keys).to match_array(%w[path_params resolved])
      expect(response.fetch('assign_ip_address_id')).to eq(ip.id)
      ip.update!(user: SpecSeed.other_user)
      read("/ip_release_requests/#{request.id}/addresses")
      expect_status(200)
      response = JSON.parse(last_response.body).fetch('response').fetch('addresses').first
      expect(response.fetch('assign_ip_address_id')).to be_nil
      expect(response.fetch('protection')).to eq('changed')
      expect(last_response.body).not_to include(SpecSeed.other_user.login, 'last_result', 'cleanup_state', 'release_chain')
    end
  end

  it 'accepts a campaign larger than one page and paginates all of its addresses' do
    c = with_current_context do
      network = SpecSeed.network_v6
      ips = 501.times.map do |i|
        create_ip_address!(network:, user: SpecSeed.user, addr: "2001:db8::#{(i + 256).to_s(16)}")
      end
      IpReleaseCampaign.create_selected!(ids: ips.map(&:id), actor: SpecSeed.admin, deadline: Time.now)
    end
    as(SpecSeed.admin) do
      read('/ip_release_campaigns')
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('response').fetch('ip_release_campaigns').first)
        .to include('total_ip_count' => 501, 'to_release_ip_count' => 501, 'kept_ip_count' => 0)
      read("/ip_release_campaigns/#{c.id}")
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('response').fetch('ip_release_campaign'))
        .to include('total_ip_count' => 501, 'to_release_ip_count' => 501, 'kept_ip_count' => 0)
      read("/ip_release_campaigns/#{c.id}/addresses", address: { limit: 500 })
      expect_status(200)
      rows = JSON.parse(last_response.body).fetch('response').fetch('addresses')
      expect(rows.length).to eq(500)
      read("/ip_release_campaigns/#{c.id}/addresses", address: { limit: 500, from_id: rows.last.fetch('id') })
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('response').fetch('addresses').length).to eq(1)
    end
    as(SpecSeed.user) do
      read("/ip_release_requests/#{c.ip_release_requests.first.id}/addresses", address: { limit: 500 })
      expect_status(200)
      rows = JSON.parse(last_response.body).fetch('response').fetch('addresses')
      expect(rows.length).to eq(500)
      expect(rows.map { |row| row.except('_meta').keys.sort }.uniq)
        .to eq([described_class::AddressParams::MEMBER_FIELDS.map(&:to_s).sort])
    end
  end

  it 'initializes counts when a campaign is expanded through a request' do
    campaign, request, item = create_fixture
    with_current_context { item.exempt!(reason: 'Reservation', actor: SpecSeed.admin) }
    as(SpecSeed.admin) do
      read('/ip_release_requests', _meta: { includes: 'ip_release_campaign' })
      expect_status(200)
      response = JSON.parse(last_response.body).fetch('response').fetch('ip_release_requests').first
      expect(response.fetch('id')).to eq(request.id)
      expect(response.fetch('ip_release_campaign')).to include(
        'id' => campaign.id, 'total_ip_count' => 1, 'to_release_ip_count' => 0, 'kept_ip_count' => 1
      )
    end
  end

  it 'lists only the member requests, including closed ones, without admin counts' do
    open_campaign, open_request = create_fixture
    closed_campaign, closed_request = create_fixture
    _other_campaign, other_request = create_fixture(user: SpecSeed.other_user)
    with_current_context { closed_campaign.close!(actor: SpecSeed.admin) }
    as(SpecSeed.user) do
      read('/ip_release_requests')
      expect_status(200)
      rows = JSON.parse(last_response.body).fetch('response').fetch('ip_release_requests')
      expect(rows.map { |row| row.fetch('id') }).to contain_exactly(open_request.id, closed_request.id)
      expect(rows.map { |row| row.except('_meta').keys }.uniq).to eq([%w[id deadline can_keep can_assign]])
      expect(rows.map { |row| row.fetch('id') }).not_to include(other_request.id)
      read("/ip_release_campaigns/#{open_campaign.id}")
      expect_status(403)
    end
  end

  it 'validates multi-select filter values before querying' do
    as(SpecSeed.admin) do
      [{ versions: '7' }, { versions: '4,' }, { networks: 'invalid' }, { locations: '-1' }, { access: 'other' }].each do |filters|
        read('/ip_release_campaigns/candidates', ip_release_campaign: filters)
        expect(JSON.parse(last_response.body).fetch('status')).to be(false)
      end
    end
  end
end
