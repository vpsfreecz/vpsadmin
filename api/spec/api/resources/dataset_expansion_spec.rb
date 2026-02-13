# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Dataset expansion actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.support
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }
  let(:support) { SpecSeed.support }
  let(:pool) { SpecSeed.pool }
  let(:node) { SpecSeed.node }

  def index_path
    vpath('/dataset_expansions')
  end

  def show_path(id)
    vpath("/dataset_expansions/#{id}")
  end

  def register_expanded_path
    vpath('/dataset_expansions/register_expanded')
  end

  def history_index_path(exp_id)
    vpath("/dataset_expansions/#{exp_id}/history")
  end

  def history_show_path(exp_id, history_id)
    vpath("/dataset_expansions/#{exp_id}/history/#{history_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def expansions
    json.dig('response', 'dataset_expansions') || []
  end

  def expansion
    json.dig('response', 'dataset_expansion') || json['response']
  end

  def histories
    json.dig('response', 'history') || json.dig('response', 'histories') || []
  end

  def history
    json.dig('response', 'history') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error'] || ''
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def expect_validation_error(field)
    keys = errors.keys.map(&:to_s)
    return expect(keys).to include(field) unless keys.empty?

    expect(msg).not_to eq('')
  end

  def create_dataset_with_vps!(user:, pool: SpecSeed.pool, node: SpecSeed.node, refquota: 1200, hostname: nil)
    hostname ||= "spec-exp-#{SecureRandom.hex(4)}"

    ds = Dataset.create!(
      name: "spec-ds-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )

    dip = DatasetInPool.create!(dataset: ds, pool: pool)

    DatasetProperty.create!(
      pool: pool,
      dataset_in_pool: dip,
      dataset: ds,
      name: 'refquota',
      value: refquota,
      inherited: false,
      confirmed: DatasetProperty.confirmed(:confirmed)
    )

    vps = Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dip,
      object_state: :active
    )

    [ds, dip, vps]
  end

  def create_primary_pool!(node: SpecSeed.node)
    pool = Pool.new(
      node: node,
      label: "Spec Primary Pool #{SecureRandom.hex(3)}",
      filesystem: "spec_primary_#{SecureRandom.hex(3)}",
      role: :primary,
      max_datasets: 10,
      is_open: true
    )
    pool.save!
    pool
  end

  def create_expansion!(dataset:, vps:, original_refquota: 1000, added_space: 200, state: :active,
                        enable_notifications: true, enable_shrink: true, stop_vps: true,
                        max_over_refquota_seconds: 3600)
    exp = DatasetExpansion.create!(
      dataset: dataset,
      vps: vps,
      state: state,
      original_refquota: original_refquota,
      added_space: added_space,
      enable_notifications: enable_notifications,
      enable_shrink: enable_shrink,
      stop_vps: stop_vps,
      max_over_refquota_seconds: max_over_refquota_seconds
    )

    dataset.update!(dataset_expansion: exp)

    exp
  end

  def create_history!(exp:, admin:, added_space:, original_refquota:, new_refquota:, created_at: nil)
    attrs = {
      admin: admin,
      added_space: added_space,
      original_refquota: original_refquota,
      new_refquota: new_refquota
    }
    attrs[:created_at] = created_at if created_at

    exp.dataset_expansion_histories.create!(attrs)
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only expansions for the current user' do
      user_ds, _, user_vps = create_dataset_with_vps!(user: user)
      other_ds, _, other_vps = create_dataset_with_vps!(user: other_user)
      user_exp = create_expansion!(dataset: user_ds, vps: user_vps)
      other_exp = create_expansion!(dataset: other_ds, vps: other_vps)

      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = expansions.map { |row| row['id'] }
      expect(ids).to include(user_exp.id)
      expect(ids).not_to include(other_exp.id)
    end

    it 'allows admin to list all expansions and includes fields' do
      user_ds, _, user_vps = create_dataset_with_vps!(user: user)
      other_ds, _, other_vps = create_dataset_with_vps!(user: other_user)
      user_exp = create_expansion!(dataset: user_ds, vps: user_vps)
      other_exp = create_expansion!(dataset: other_ds, vps: other_vps)

      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = expansions.map { |row| row['id'] }
      expect(ids).to include(user_exp.id, other_exp.id)

      row = expansions.find { |r| r['id'] == user_exp.id }
      required_keys = %w[
        id dataset vps state original_refquota added_space enable_notifications
        enable_shrink stop_vps max_over_refquota_seconds created_at
      ]
      expect(row.keys).to include(*required_keys)
      expect(rid(row['dataset'])).to eq(user_ds.id)
      expect(rid(row['vps'])).to eq(user_vps.id)
    end

    it 'supports _meta count' do
      ds1, _, vps1 = create_dataset_with_vps!(user: user)
      ds2, _, vps2 = create_dataset_with_vps!(user: other_user)
      create_expansion!(dataset: ds1, vps: vps1)
      create_expansion!(dataset: ds2, vps: vps2)

      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(2)
    end

    it 'supports limit pagination' do
      ds1, _, vps1 = create_dataset_with_vps!(user: user)
      ds2, _, vps2 = create_dataset_with_vps!(user: other_user)
      create_expansion!(dataset: ds1, vps: vps1)
      create_expansion!(dataset: ds2, vps: vps2)

      as(admin) { json_get index_path, dataset_expansion: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(expansions.length).to eq(1)
    end

    it 'supports from_id pagination' do
      ds1, _, vps1 = create_dataset_with_vps!(user: user)
      ds2, _, vps2 = create_dataset_with_vps!(user: other_user)
      ds3, _, vps3 = create_dataset_with_vps!(user: user)
      create_expansion!(dataset: ds1, vps: vps1)
      create_expansion!(dataset: ds2, vps: vps2)
      create_expansion!(dataset: ds3, vps: vps3)
      boundary = DatasetExpansion.order(:id).first.id

      as(admin) { json_get index_path, dataset_expansion: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = expansions.map { |row| row['id'] }
      expect(ids).not_to be_empty
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      json_get show_path(exp.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own expansion' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(user) { json_get show_path(exp.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(expansion['id']).to eq(exp.id)
      expect(rid(expansion['dataset'])).to eq(ds.id)
      expect(rid(expansion['vps'])).to eq(vps.id)
    end

    it 'returns 404 for other user' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(user) { json_get show_path(exp.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any expansion' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(admin) { json_get show_path(exp.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(expansion['id']).to eq(exp.id)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, dataset_expansion: { dataset: 1, added_space: 200, max_over_refquota_seconds: 3600 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      ds, = create_dataset_with_vps!(user: user)

      as(user) do
        json_post index_path, dataset_expansion: { dataset: ds.id, added_space: 200, max_over_refquota_seconds: 3600 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      ds, = create_dataset_with_vps!(user: user)

      as(support) do
        json_post index_path, dataset_expansion: { dataset: ds.id, added_space: 200, max_over_refquota_seconds: 3600 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create an expansion and creates a transaction chain' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      payload = {
        dataset_expansion: {
          dataset: ds.id,
          added_space: 200,
          enable_notifications: false,
          enable_shrink: true,
          stop_vps: false,
          max_over_refquota_seconds: 3600
        }
      }

      allow(TransactionChains::Vps::ExpandDataset).to receive(:fire) do |exp|
        chain = TransactionChain.create!(
          name: 'spec_expand_dataset',
          type: TransactionChains::Vps::ExpandDataset.name,
          state: :queued,
          size: 1,
          user: User.current,
          user_session: UserSession.current,
          concern_type: :chain_affect
        )

        exp.original_refquota ||= 1000
        exp.max_over_refquota_seconds ||= 3600
        exp.save!

        exp.dataset.update!(dataset_expansion: exp)

        exp.dataset_expansion_histories.create!(
          admin: User.current,
          added_space: exp.added_space,
          original_refquota: exp.original_refquota,
          new_refquota: exp.original_refquota + exp.added_space
        )

        [chain, exp]
      end

      expect do
        as(admin) { json_post index_path, payload }
      end.to change(DatasetExpansion, :count).by(1)
                                             .and change(TransactionChain, :count).by(1)
                                             .and change(DatasetExpansionHistory, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      ds.reload
      expect(ds.dataset_expansion_id).not_to be_nil

      response_expansion = expansion
      expect(response_expansion['added_space']).to eq(200)
      expect(rid(response_expansion['dataset'])).to eq(ds.id)
      expect(rid(response_expansion['vps'])).to eq(vps.id)
    end

    it 'rejects already expanded datasets' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      create_expansion!(dataset: ds, vps: vps)

      as(admin) do
        json_post index_path, dataset_expansion: {
          dataset: ds.id,
          added_space: 200,
          max_over_refquota_seconds: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('this dataset is already expanded')
    end

    it 'rejects non-hypervisor datasets' do
      primary_pool = create_primary_pool!(node: node)
      ds, = create_dataset_with_vps!(user: user, pool: primary_pool)

      as(admin) do
        json_post index_path, dataset_expansion: {
          dataset: ds.id,
          added_space: 200,
          max_over_refquota_seconds: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('only hypervisor datasets can be expanded')
    end

    it 'returns validation errors for missing dataset' do
      as(admin) do
        json_post index_path, dataset_expansion: { added_space: 200, max_over_refquota_seconds: 3600 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect_validation_error('dataset')
    end

    it 'returns validation errors for missing added_space' do
      ds, = create_dataset_with_vps!(user: user)

      as(admin) do
        json_post index_path, dataset_expansion: { dataset: ds.id, max_over_refquota_seconds: 3600 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect_validation_error('added_space')
    end

    it 'returns validation errors for missing max_over_refquota_seconds' do
      ds, = create_dataset_with_vps!(user: user)

      as(admin) do
        json_post index_path, dataset_expansion: { dataset: ds.id, added_space: 200 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect_validation_error('max_over_refquota_seconds')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      json_put show_path(exp.id), dataset_expansion: { enable_notifications: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(user) { json_put show_path(exp.id), dataset_expansion: { enable_notifications: false } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(support) { json_put show_path(exp.id), dataset_expansion: { enable_notifications: false } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update fields' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(
        dataset: ds,
        vps: vps,
        enable_notifications: true,
        enable_shrink: true,
        stop_vps: true,
        max_over_refquota_seconds: 3600
      )

      as(admin) do
        json_put show_path(exp.id), dataset_expansion: {
          enable_notifications: false,
          enable_shrink: false,
          stop_vps: false,
          max_over_refquota_seconds: 7200
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      exp.reload
      expect(exp.enable_notifications).to be(false)
      expect(exp.enable_shrink).to be(false)
      expect(exp.stop_vps).to be(false)
      expect(exp.max_over_refquota_seconds).to eq(7200)
    end

    it 'coerces max_over_refquota_seconds to an integer' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(admin) { json_put show_path(exp.id), dataset_expansion: { max_over_refquota_seconds: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(true)

      exp.reload
      expect(exp.max_over_refquota_seconds).to eq(0)
    end
  end

  describe 'RegisterExpanded' do
    it 'rejects unauthenticated access' do
      json_post register_expanded_path, dataset_expansion: { dataset: 1, original_refquota: 1000 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      ds, = create_dataset_with_vps!(user: user)

      as(user) { json_post register_expanded_path, dataset_expansion: { dataset: ds.id, original_refquota: 1000 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      ds, = create_dataset_with_vps!(user: user)

      as(support) { json_post register_expanded_path, dataset_expansion: { dataset: ds.id, original_refquota: 1000 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to register an already expanded dataset' do
      ds, = create_dataset_with_vps!(user: user, refquota: 1200)
      payload = {
        dataset_expansion: {
          dataset: ds.id,
          original_refquota: 1000,
          enable_notifications: true,
          enable_shrink: true,
          stop_vps: true,
          max_over_refquota_seconds: 3600
        }
      }

      expect do
        as(admin) { json_post register_expanded_path, payload }
      end.to change(DatasetExpansion, :count).by(1)
                                             .and change(DatasetExpansionHistory, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      ds.reload
      expect(ds.dataset_expansion_id).not_to be_nil

      response_expansion = expansion
      expect(response_expansion['original_refquota']).to eq(1000)
      expect(response_expansion['added_space']).to eq(200)
    end

    it 'rejects already expanded datasets' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      create_expansion!(dataset: ds, vps: vps)

      as(admin) do
        json_post register_expanded_path, dataset_expansion: {
          dataset: ds.id,
          original_refquota: 1000,
          max_over_refquota_seconds: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('this dataset is already expanded')
    end

    it 'rejects non-hypervisor datasets' do
      primary_pool = create_primary_pool!(node: node)
      ds, = create_dataset_with_vps!(user: user, pool: primary_pool, refquota: 1200)

      as(admin) do
        json_post register_expanded_path, dataset_expansion: {
          dataset: ds.id,
          original_refquota: 1000,
          max_over_refquota_seconds: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('only hypervisor datasets can be expanded')
    end

    it 'rejects invalid original_refquota values' do
      ds, = create_dataset_with_vps!(user: user, refquota: 1200)

      as(admin) do
        json_post register_expanded_path, dataset_expansion: {
          dataset: ds.id,
          original_refquota: 1200,
          max_over_refquota_seconds: 3600
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('invalid parameters')
      orig_errors = errors['original_refquota'] || errors[:original_refquota] || []
      expect(orig_errors).to include('must be lesser than current refquota')
    end
  end

  describe 'History Index' do
    it 'rejects unauthenticated access' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      json_get history_index_path(exp.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists history in ascending order for the owner' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)
      older = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100,
        created_at: Time.utc(2024, 1, 1, 12, 0, 0)
      )
      newer = create_history!(
        exp: exp,
        admin: admin,
        added_space: 50,
        original_refquota: 1100,
        new_refquota: 1150,
        created_at: Time.utc(2024, 1, 2, 12, 0, 0)
      )

      as(user) { json_get history_index_path(exp.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = histories.map { |row| row['id'] }
      expect(ids).to eq([older.id, newer.id])

      row = histories.first
      required_keys = %w[id added_space original_refquota new_refquota created_at admin]
      expect(row.keys).to include(*required_keys)
    end

    it 'returns empty list for other users' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)
      create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      as(user) { json_get history_index_path(exp.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(histories).to eq([])
    end

    it 'allows admin to list history' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)
      hist = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      as(admin) { json_get history_index_path(exp.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = histories.map { |row| row['id'] }
      expect(ids).to include(hist.id)
      expect(rid(histories.first['admin'])).to eq(admin.id)
    end

    it 'supports limit and from_id pagination' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)
      h1 = create_history!(
        exp: exp,
        admin: admin,
        added_space: 10,
        original_refquota: 1000,
        new_refquota: 1010
      )
      h2 = create_history!(
        exp: exp,
        admin: admin,
        added_space: 20,
        original_refquota: 1010,
        new_refquota: 1030
      )
      create_history!(
        exp: exp,
        admin: admin,
        added_space: 30,
        original_refquota: 1030,
        new_refquota: 1060
      )

      as(user) { json_get history_index_path(exp.id), history: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(histories.length).to eq(1)

      as(user) { json_get history_index_path(exp.id), history: { from_id: h1.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = histories.map { |row| row['id'] }
      expect(ids).to all(be > h1.id)
      expect(ids).to include(h2.id)
    end
  end

  describe 'History Show' do
    it 'rejects unauthenticated access' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)
      hist = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      json_get history_show_path(exp.id, hist.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own history row' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)
      hist = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      as(user) { json_get history_show_path(exp.id, hist.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(history['id']).to eq(hist.id)
    end

    it 'returns 404 for other user' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)
      hist = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      as(user) { json_get history_show_path(exp.id, hist.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any history row' do
      ds, _, vps = create_dataset_with_vps!(user: other_user)
      exp = create_expansion!(dataset: ds, vps: vps)
      hist = create_history!(
        exp: exp,
        admin: admin,
        added_space: 100,
        original_refquota: 1000,
        new_refquota: 1100
      )

      as(admin) { json_get history_show_path(exp.id, hist.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(history['id']).to eq(hist.id)
    end

    it 'returns 404 for unknown history id' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)
      missing = DatasetExpansionHistory.maximum(:id).to_i + 10

      as(user) { json_get history_show_path(exp.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'History Create' do
    it 'rejects unauthenticated access' do
      json_post history_index_path(1), history: { added_space: 50 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(user) { json_post history_index_path(exp.id), history: { added_space: 50 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(support) { json_post history_index_path(exp.id), history: { added_space: 50 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to add expansion history and creates a transaction chain' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps, original_refquota: 1000, added_space: 200)

      allow(TransactionChains::Vps::ExpandDatasetAgain).to receive(:fire) do |hist|
        chain = TransactionChain.create!(
          name: 'spec_expand_dataset_again',
          type: TransactionChains::Vps::ExpandDatasetAgain.name,
          state: :queued,
          size: 1,
          user: User.current,
          user_session: UserSession.current,
          concern_type: :chain_affect
        )

        expansion = hist.dataset_expansion
        current_refquota = expansion.original_refquota + expansion.added_space

        hist.original_refquota ||= current_refquota
        hist.new_refquota ||= current_refquota + hist.added_space
        hist.save!

        expansion.update!(added_space: expansion.added_space + hist.added_space)

        [chain, hist]
      end

      expect do
        as(admin) { json_post history_index_path(exp.id), history: { added_space: 50 } }
      end.to change(TransactionChain, :count).by(1)
                                             .and change(DatasetExpansionHistory, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      exp.reload
      expect(exp.added_space).to eq(250)
    end

    it 'rejects resolved expansions' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps, state: :resolved)

      as(admin) { json_post history_index_path(exp.id), history: { added_space: 50 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('this expansion is already resolved')
    end

    it 'returns validation errors for missing added_space' do
      ds, _, vps = create_dataset_with_vps!(user: user)
      exp = create_expansion!(dataset: ds, vps: vps)

      as(admin) { json_post history_index_path(exp.id), history: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect_validation_error('added_space')
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
