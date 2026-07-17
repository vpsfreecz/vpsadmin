# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Node::KernelHistory' do
  let(:node) { SpecSeed.node }
  let(:t0) { Time.utc(2026, 7, 1, 12, 0, 0) }

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    node.node_kernel_events.delete_all
  end

  def index_path(node_id = node.id)
    vpath("/nodes/#{node_id}/kernel_history")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def events
    json.dig('response', 'kernel_histories') || []
  end

  it 'publishes the kernel history action in the API description' do
    scopes = EndpointInventory.scopes_for_version(self, api_version)

    expect(scopes).to include('node.kernel_history#index')
  end

  it 'allows logged-in users to read sanitized history' do
    NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      boot_id: 'private-boot-id',
      booted_at: t0,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      effective_at: t0,
      observed_before: t0 + 5,
      current: true
    )

    as(SpecSeed.user) { json_get index_path }

    expect(last_response.status).to eq(200)
    expect(json['status']).to be(true)
    expect(events.length).to eq(1)
    expect(events.first).to include(
      'event_type' => 'boot',
      'booted_release' => '6.12.95',
      'reported_release' => '6.12.95',
      'confidence' => 'exact',
      'current' => true
    )
    expect(events.first).not_to have_key('node_id')
    expect(events.first).not_to have_key('boot_id')
    expect(events.first).not_to have_key('evidence')
  end

  it 'rejects unauthenticated requests' do
    json_get index_path

    expect(last_response.status).to eq(401)
  end

  it 'does not expose inactive node history' do
    node.update!(active: false)

    NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :reconstructed_node_status,
      confidence: :inferred,
      booted_at: t0,
      booted_release: '6.12.95',
      reported_release: '6.12.95',
      observed_before: t0 + 5,
      current: true
    )

    as(SpecSeed.user) { json_get index_path }

    expect(last_response.status).to eq(404)
  ensure
    node.update!(active: true)
  end

  it 'returns newest events first with a stable id tie-breaker' do
    older = NodeKernelEvent.create!(
      node:,
      event_type: :boot,
      source: :node_report,
      confidence: :exact,
      booted_release: '6.12.93',
      reported_release: '6.12.93',
      observed_before: t0
    )
    same_time_first = NodeKernelEvent.create!(
      node:,
      event_type: :reported_release_change,
      source: :node_report,
      confidence: :exact,
      booted_release: '6.12.93',
      reported_release: '6.12.93.1',
      observed_before: t0 + 1.hour
    )
    same_time_last = NodeKernelEvent.create!(
      node:,
      event_type: :livepatch_change,
      source: :node_report,
      confidence: :exact,
      booted_release: '6.12.93',
      reported_release: '6.12.93.2',
      observed_before: t0 + 1.hour
    )

    as(SpecSeed.user) { json_get index_path }

    expect(events.map { |event| event['id'] }).to eq(
      [same_time_last.id, same_time_first.id, older.id]
    )
  end

  it 'does not expose kernel history for service-only nodes' do
    node.update!(role: :mailer)

    as(SpecSeed.user) { json_get index_path }

    expect(last_response.status).to eq(404)
  ensure
    node.update!(role: :node)
  end
end
