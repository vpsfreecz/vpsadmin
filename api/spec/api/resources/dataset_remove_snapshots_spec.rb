require 'spec_helper'

RSpec.describe 'Dataset snapshot removal' do # rubocop:disable RSpec/DescribeClass
  let(:fixture) do
    create_dataset_pair!(user: SpecSeed.user, pool: create_pool!(node: SpecSeed.node, role: :primary),
                         backup_pool: create_pool!(node: SpecSeed.other_node, role: :backup))
  end
  let(:dataset) { fixture[0] }
  let(:source) { fixture[1] }
  let(:target) { fixture[2] }

  def submit(action, payload = {})
    post vpath("/datasets/#{dataset.id}/#{action}"), JSON.generate(dataset: payload), 'CONTENT_TYPE' => 'application/json'
  end

  def digest
    VpsAdmin::API::Operations::Dataset::RemoveSnapshots.new.prepare(dataset, chain: nil, recursive: false, disable_plans: true)
                                                       .inventory.fetch(:manifest_digest)
  end

  before do
    header 'Accept', 'application/json'
    target
  end

  after do |example|
    next unless example.metadata[:no_transaction]

    SnapshotInPoolInBranch.joins(:snapshot_in_pool).where(snapshot_in_pools: { dataset_in_pool_id: target.id }).delete_all
    SnapshotInPool.where(dataset_in_pool: [source, target]).delete_all
    Snapshot.where(dataset: dataset).delete_all
    Branch.where(dataset_tree: target.dataset_trees).delete_all
    DatasetTree.where(dataset_in_pool: target).delete_all
    ids = DatasetProperty.where(dataset_in_pool: [source, target]).pluck(:id)
    DatasetPropertyHistory.where(dataset_property_id: ids).delete_all
    DatasetProperty.where(id: ids).delete_all
    DatasetInPool.where(id: [source.id, target.id]).delete_all
    Dataset.where(id: dataset.id).delete_all
    DatasetProperty.where(pool_id: [source.pool_id, target.pool_id]).delete_all
    Pool.where(id: [source.pool_id, target.pool_id]).delete_all
  end

  it 'serializes a complete preview in the ordinary dataset envelope without a receipt', :no_transaction do
    snapshot, = create_snapshot!(dataset:, dip: source, name: 'reviewed-snapshot')
    tree = create_tree!(dip: target)
    branch = create_branch!(tree:, name: 'history')
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot:, dip: target), branch:)
    as(SpecSeed.admin) { submit('preview_snapshot_removal') }
    expect(json['status']).to be(true), last_response.body
    output = json.dig('response', 'dataset')
    expect(output.keys).to match_array(%w[manifest_version manifest_digest manifest])
    expect(output['manifest_version']).to eq(1)
    expect(output['manifest_digest']).to match(/\Av1:[0-9a-f]{64}\z/)
    expect(output.dig('manifest', 'options')).to eq('recursive' => false, 'disable_plans' => true)
    expect(output.dig('manifest', 'counts')).to include('datasets' => 1, 'copies' => 2, 'snapshot_locations' => 2)
    expect(json.dig('response', '_meta', 'action_state_id')).to be_nil
    if ENV['SNAPSHOT_REMOVAL_FIXTURES']
      File.write(File.join(ENV.fetch('SNAPSHOT_REMOVAL_FIXTURES'), 'preview.json'), JSON.pretty_generate(json))
    end
  end

  %w[preview_snapshot_removal remove_snapshots].each do |action|
    it "denies unauthenticated #{action}" do
      submit(action)
      expect(last_response.status).to eq(401)
    end

    %i[user other_user].each do |role|
      it "denies #{role} #{action}" do
        as(SpecSeed.public_send(role)) { submit(action) }
        expect(last_response.status).to eq(403)
      end
    end

    it "denies support #{action} independently of ownership" do
      support = SpecSeed.user
      support.update!(level: 21)
      as(support) { submit(action) }
      expect(last_response.status).to eq(403)
    end
  end

  it 'returns the normal empty dataset and task receipt for empty history' do
    as(SpecSeed.admin) { submit('remove_snapshots', manifest_digest: digest) }
    expect(json['status']).to be(true), last_response.body
    expect(json.dig('response', 'dataset')).to eq({})
    expect(json.dig('response', '_meta', 'action_state_id')).to be_a(Integer)
  end

  it 'advertises Custom inventory and required digest through ordinary action descriptions' do
    as(SpecSeed.admin) { options "#{vpath("/datasets/#{dataset.id}/preview_snapshot_removal")}?method=POST" }
    expect(json.dig('response', 'output', 'parameters', 'manifest', 'type')).to eq('Custom'), last_response.body
    preview_description = json
    as(SpecSeed.admin) { options "#{vpath("/datasets/#{dataset.id}/remove_snapshots")}?method=POST" }
    expect(json.dig('response', 'input', 'parameters', 'manifest_digest', 'required')).to be(true), last_response.body
    if ENV['SNAPSHOT_REMOVAL_FIXTURES']
      File.write(File.join(ENV.fetch('SNAPSHOT_REMOVAL_FIXTURES'), 'description.json'), JSON.pretty_generate(preview_description))
    end
  end

  it 'requires a reviewed digest' do
    as(SpecSeed.admin) { submit('remove_snapshots') }
    expect(json['status']).to be(false)
    expect(json.fetch('errors')).to have_key('manifest_digest')
  end

  it 'returns a stable top-level stale marker with no queued task' do
    before = TransactionChain.count
    as(SpecSeed.admin) { submit('remove_snapshots', manifest_digest: "v1:#{'0' * 64}") }
    expect(json['status']).to be(false)
    expect(json.fetch('errors')).to eq('manifest_digest' => ['stale_preview'])
    expect(json['message']).to be_a(String)
    expect(TransactionChain.count).to eq(before)
    if ENV['SNAPSHOT_REMOVAL_FIXTURES']
      File.write(File.join(ENV.fetch('SNAPSHOT_REMOVAL_FIXTURES'), 'stale.json'), JSON.pretty_generate(json))
    end
  end
end
