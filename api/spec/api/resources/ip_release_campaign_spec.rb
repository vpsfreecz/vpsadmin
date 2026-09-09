require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::IpReleaseCampaign do
  before do
    header 'Accept', 'application/json'
    ensure_signer_unlocked!
  end

  def create_fixture(user: SpecSeed.user)
    with_current_context do
      ip = create_ip_address!(user:)
      ip.update!(charged_environment: SpecSeed.environment)
      campaign = IpReleaseCampaign.create_selected!(ids: [ip.id], actor: SpecSeed.admin,
                                                    label: 'Unused IPv4', deadline: Time.now + 604_800)
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

  it 'lets an admin preview and create a campaign with seven-day and opt-out defaults' do
    ip = with_current_context { create_ip_address!(user: SpecSeed.user) }
    as(SpecSeed.admin) do
      read('/ip_release_campaigns/candidates')
      expect_status(200)
      expect(last_response.body).to include(ip.addr)
      write('/ip_release_campaigns', ip_release_campaign: { label: 'Recover', addresses: [ip.id] })
      expect_status(200)
    end
    c = IpReleaseCampaign.last
    expect(c.allow_keep).to be(true)
    expect(c.deadline).to be_within(10).of(Time.now + 604_800)
  end

  it 'paginates candidate selections and rejects oversized campaigns' do
    ips = with_current_context { Array.new(2) { create_ip_address!(user: SpecSeed.user) } }
    as(SpecSeed.admin) do
      read('/ip_release_campaigns/candidates', ip_release_campaign: { limit: 1, from_id: ips.first.id - 1 })
      expect_status(200)
      expect(last_response.body).to include(ips.first.addr)
      expect(last_response.body).not_to include(ips.last.addr)
      read('/ip_release_campaigns/candidates', ip_release_campaign: { limit: 1, from_id: ips.first.id })
      expect_status(200)
      expect(last_response.body).to include(ips.last.addr)
      write('/ip_release_campaigns', ip_release_campaign: { label: 'Too large', addresses: (1..101).to_a })
      expect_status(200)
      expect(JSON.parse(last_response.body).fetch('status')).to be(false)
      expect(last_response.body).to include('100')
    end
    expect(IpReleaseCampaign.count).to eq(0)
  end

  it 'shows notice history only to its owner and administrators' do
    c, request = create_fixture
    with_current_context do
      ensure_available_node_status!(SpecSeed.node)
      ensure_user_mail_templates!
      c.notify!(event: 'requested', actor: SpecSeed.admin)
      c.notify!(event: 'reminder', actor: SpecSeed.admin)
    end
    as(SpecSeed.user) do
      read("/ip_release_requests/#{request.id}/notices")
      expect_status(200)
      expect(last_response.body).to include('requested', 'reminder')
      expect(last_response.body).not_to include('mail_log', 'created_by')
    end
    as(SpecSeed.admin) do
      read("/ip_release_requests/#{request.id}/notices")
      expect_status(200)
      expect(last_response.body).to include('mail_log', 'created_by')
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
      read('/ip_release_campaigns')
      expect_status(200)
      expect(last_response.body).to include(campaign.label)
      read("/ip_release_campaigns/#{campaign.id}")
      expect_status(200)
      expect(last_response.body).to include(campaign.label)
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
  end

  it 'denies campaign management to ordinary users and support staff' do
    c, request, item = create_fixture
    [SpecSeed.user, SpecSeed.support].each do |user|
      as(user) do
        read('/ip_release_campaigns')
        expect_status(403)
        read('/ip_release_campaigns/candidates')
        expect_status(403)
        %w[release close notify].each do |action|
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
      expect_status(404)
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
    expect(ip.reload.user_id).to be_nil
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
end
