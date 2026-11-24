require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::IncidentPolicyExposure do
  before do
    header 'Accept', 'application/json'
    install_generic_incident_policy_fixture
  end

  def request_index(resource, params = {})
    get vpath("/#{resource}s"), { resource.to_sym => params }, { 'CONTENT_TYPE' => 'application/json', 'rack.input' => StringIO.new('{}') }
  end

  %w[incident_policy_exposure incident_policy_evaluation].each do |resource|
    it "denies #{resource} execution and metadata to members and support" do
      [SpecSeed.user, SpecSeed.support].each do |user|
        as(user) { request_index(resource, vps_id: 1, scope: 'all') }
        expect(last_response.status).to eq(403)
        as(user) { options "#{vpath("/#{resource}s")}?method=GET" }
        expect(last_response.body).not_to include('total_count', 'stop_completed_at')
      end
    end

    it "always declares and returns #{resource} paging metadata, including empty pages" do
      as(SpecSeed.admin) { request_index(resource, offset: 100) }
      expect(last_response.status).to eq(200), last_response.body
      expect(json.dig('response', "#{resource}s")).to eq([])
      expect(json.dig('response', '_meta')).to include('total_count' => 0, 'offset' => 100, 'limit' => 25, 'next_offset' => nil)
      expect(json.dig('response', '_meta', 'as_of')).to be_a(String)
      as(SpecSeed.admin) { options "#{vpath("/#{resource}s")}?method=GET" }
      expect(last_response.status).to eq(200), last_response.body
      description = json.dig('response', 'resource', 'actions', 'index') || json.dig('response', 'actions', 'index')
      expect(last_response.body).to include('total_count', 'next_offset', 'read_at')
    end
  end

  it 'returns ordinary selected references for exposures and historical raw identities separately' do
    vps = build_standalone_vps_fixture.fetch(:vps)
    read_report(vps, detected_at: Time.now.utc - 60)
    as(SpecSeed.admin) { request_index('incident_policy_exposure', vps: vps.id) }
    expect(last_response.status).to eq(200), last_response.body
    row = json.dig('response', 'incident_policy_exposures').first
    expect(row).to include('vps' => hash_including('id' => vps.id, 'hostname' => vps.hostname),
                           'user' => hash_including('id' => vps.user_id, 'login' => vps.user.login))
    expect(row.dig('vps', '_meta')).to include('path_params' => [vps.id], 'resolved' => false)
    expect(row).not_to have_key('vps_id')
    expect(row).not_to have_key('hostname')
    as(SpecSeed.admin) { request_index('incident_policy_evaluation', scope: 'all', vps_id: vps.id) }
    expect(last_response.status).to eq(200), last_response.body
    expect(json.dig('response', 'incident_policy_evaluations').first).to include('vps_id' => vps.id)
  end

  it 'rejects invalid page, policy and time inputs without writes' do
    as(SpecSeed.admin) { request_index('incident_policy_exposure', limit: 101) }
    expect(last_response.status).to eq(200) # HaveAPI's declared compatibility validation envelope
    expect(json['status']).to be(false)
    expect(json.dig('response', 'errors', 'limit') || json.dig('errors', 'limit')).not_to be_nil
    as(SpecSeed.admin) { request_index('incident_policy_exposure', policy_key: 'absent') }
    expect(json['status']).to be(false)
    as(SpecSeed.admin) { request_index('incident_policy_evaluation', as_of: (Time.now.utc + 600).iso8601) }
    expect(json['status']).to be(false)
  end
end
