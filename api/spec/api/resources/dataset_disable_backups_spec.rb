# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dataset.DisableBackups' do # rubocop:disable RSpec/DescribeClass
  let(:fixture) do
    create_dataset_pair!(user: SpecSeed.user, pool: create_pool!(node: SpecSeed.node, role: :primary),
                         backup_pool: create_pool!(node: SpecSeed.node, role: :backup))
  end
  let(:dataset) { fixture[0] }
  let(:source) { fixture[1] }
  let(:target) { fixture[2] }

  def submit(payload = {})
    post vpath("/datasets/#{dataset.id}/disable_backups"), JSON.generate(dataset: payload), 'CONTENT_TYPE' => 'application/json'
  end

  before do
    header 'Accept', 'application/json'
    target
    create_port_reservations!(node: target.pool.node)
  end

  it 'denies unauthenticated callers' do
    submit
    expect(last_response.status).to eq(401)
  end

  %i[user other_user].each do |role|
    it "denies #{role} even for an empty owned source" do
      as(SpecSeed.public_send(role)) { submit }
      expect(last_response.status).to eq(403)
    end
  end

  it 'denies the support role independently of dataset ownership' do
    support = SpecSeed.user
    support.update!(level: 21)
    as(support) { submit }
    expect(last_response.status).to eq(403)
  end

  it 'returns the ordinary action-state receipt even for empty metadata-only work' do
    as(SpecSeed.admin) { submit }
    expect(json['status']).to be(true), last_response.body
    expect(json.dig('response', '_meta', 'action_state_id')).to be_a(Integer)
    expect(json.fetch('response').keys).to match_array(%w[dataset _meta])
    expect(json.dig('response', 'dataset')).to eq({})
  end

  it 'defaults to backup-first and accepts one task containing transfer and deletion' do
    create_snapshot!(dataset: dataset, dip: source)
    as(SpecSeed.admin) { submit }
    expect(json['status']).to be(true), last_response.body
    chain = TransactionChains::Dataset::DisableBackups.find(json.dig('response', '_meta', 'action_state_id'))
    expect(tx_classes(chain)).to include(Transactions::Storage::LocalSend, Transactions::Storage::DestroySnapshot)
    expect(json.fetch('response').keys).to match_array(%w[dataset _meta])
    expect(json.dig('response', 'dataset')).to eq({})
  end

  it 'honors explicit opt-out without requiring a backup destination' do
    create_snapshot!(dataset: dataset, dip: source)
    target.pool.update!(is_open: false)
    as(SpecSeed.admin) { submit(backup_first: false) }
    expect(json['status']).to be(true), last_response.body
    chain = TransactionChains::Dataset::DisableBackups.find(json.dig('response', '_meta', 'action_state_id'))
    expect(tx_classes(chain)).not_to include(Transactions::Storage::LocalSend)
    expect(tx_classes(chain)).to include(Transactions::Storage::DestroySnapshot)
  end

  it 'leaves backup heads unchanged on ordinary first-plan assignment' do
    tree = create_tree!(dip: target)
    branch = create_branch!(tree: tree, name: 'restored-history')
    _, plan = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
    as(SpecSeed.admin) do
      post vpath("/datasets/#{dataset.id}/plans"), JSON.generate(plan: { environment_dataset_plan: plan.id }),
           'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(true), last_response.body
    expect(tree.reload.head).to be(true)
    expect(branch.reload.head).to be(true)
  end

  it 'excludes plan mutation while a storage operation holds the source lock' do
    _, plan = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
    source.acquire_lock
    as(SpecSeed.admin) do
      post vpath("/datasets/#{dataset.id}/plans"), JSON.generate(plan: { environment_dataset_plan: plan.id }),
           'CONTENT_TYPE' => 'application/json'
    end
    expect(json['status']).to be(false)
    expect(source.dataset_in_pool_plans).to be_empty
  end

  %i[create delete].each do |operation|
    it "rechecks plan #{operation} ownership after locking a transferred source" do
      _, env = create_daily_backup_env_plan!(environment: source.pool.node.location.environment)
      plan = source.add_plan(env) if operation == :delete
      allow(VpsAdmin::API::DatasetPlans).to receive(:with_locked_source).and_wrap_original do |original, selected, **kwargs, &block|
        selected.update!(user: SpecSeed.other_user)
        original.call(selected, **kwargs, &block)
      end
      as(SpecSeed.user) do
        if operation == :create
          post vpath("/datasets/#{dataset.id}/plans"), JSON.generate(plan: { environment_dataset_plan: env.id }),
               'CONTENT_TYPE' => 'application/json'
        else
          delete vpath("/datasets/#{dataset.id}/plans/#{plan.id}"), {}, 'CONTENT_TYPE' => 'application/json',
                                                                        'rack.input' => StringIO.new('{}')
        end
      end
      expect(json['status']).to be(false), last_response.body
      expect(source.dataset_in_pool_plans.count).to eq(operation == :delete ? 1 : 0)
    end
  end
end
