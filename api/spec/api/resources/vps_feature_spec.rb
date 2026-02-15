# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VPS::Feature' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path(vps_id)
    vpath("/vpses/#{vps_id}/features")
  end

  def show_path(vps_id, feature_id)
    vpath("/vpses/#{vps_id}/features/#{feature_id}")
  end

  def update_path(vps_id, feature_id)
    vpath("/vpses/#{vps_id}/features/#{feature_id}")
  end

  def update_all_path(vps_id)
    vpath("/vpses/#{vps_id}/features/update_all")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def features
    json.dig('response', 'features') || []
  end

  def feature_obj
    json.dig('response', 'feature') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dip = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dip,
      object_state: :active
    )
  end

  def create_features!(vps)
    VpsFeature::FEATURES.each_key do |name|
      feat = VpsFeature.new(vps: vps, name: name.to_s)
      feat.set_to_default
      feat.save!
    end

    vps.reload
  end

  let!(:user_vps) do
    vps = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    create_features!(vps)
    vps
  end

  let!(:other_vps) do
    vps = create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'spec-other-vps')
    create_features!(vps)
    vps
  end

  let!(:user_feature) { user_vps.vps_features.find_by!(name: 'tun') }
  let!(:other_feature) { other_vps.vps_features.find_by!(name: 'tun') }

  describe 'API description' do
    it 'includes vps feature endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'vps.feature#index',
        'vps.feature#show',
        'vps.feature#update',
        'vps.feature#update_all'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user_vps.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists features for owned VPS' do
      as(SpecSeed.user) { json_get index_path(user_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      list = features
      expect(list).to be_an(Array)
      names = list.map { |row| row['name'] }
      expect(names).to include(*VpsFeature::FEATURES.keys.map(&:to_s))

      row = list.find { |item| item['name'] == 'tun' }
      expect(row).not_to be_nil
      expect(row.keys).to include('id', 'name', 'label', 'enabled')
      expect(row['label']).to eq('TUN/TAP')
    end

    it 'hides other user VPS features' do
      as(SpecSeed.user) { json_get index_path(other_vps.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list any VPS features' do
      as(SpecSeed.admin) { json_get index_path(other_vps.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'rejects negative limit' do
      as(SpecSeed.user) { json_get index_path(user_vps.id), feature: { limit: -1 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('limit')
    end

    it 'rejects negative from_id' do
      as(SpecSeed.user) { json_get index_path(user_vps.id), feature: { from_id: -1 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('from_id')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_vps.id, user_feature.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows feature for owned VPS' do
      as(SpecSeed.user) { json_get show_path(user_vps.id, user_feature.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(feature_obj['id']).to eq(user_feature.id)
      expect(feature_obj['name']).to eq('tun')
      expect(feature_obj['label']).to eq('TUN/TAP')
      expect(feature_obj).to include('enabled')
    end

    it 'hides other user VPS feature' do
      as(SpecSeed.user) { json_get show_path(other_vps.id, other_feature.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown feature id' do
      missing_id = VpsFeature.maximum(:id).to_i + 100

      as(SpecSeed.user) { json_get show_path(user_vps.id, missing_id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    before do
      ensure_signer_unlocked!
    end

    it 'rejects unauthenticated access' do
      json_put update_path(user_vps.id, user_feature.id), feature: { enabled: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to toggle a feature' do
      target = !user_feature.enabled

      expect do
        as(SpecSeed.user) do
          json_put update_path(user_vps.id, user_feature.id), feature: { enabled: target }
        end
      end.to change(TransactionChain, :count).by(1)
         .and change(Transaction, :count).by(1)
         .and change(ObjectHistory, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      chain = TransactionChain.find(action_state_id)
      expect(chain.user_id).to eq(SpecSeed.user.id)
      expect(chain.type).to eq('TransactionChains::Vps::Features')
      expect(chain.name).to eq('features')
      expect(chain.state).to eq('queued')
      expect(chain.size).to eq(1)
      expect(chain.concern_type).to eq('chain_affect')
      expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', user_vps.id])

      transaction = chain.transactions.first
      expect(transaction.handle).to eq(8001)
      expect(transaction.vps_id).to eq(user_vps.id)

      confirmation = TransactionConfirmation.where(
        transaction_id: transaction.id,
        class_name: 'VpsFeature',
        confirm_type: :edit_after_type
      ).find { |row| row.row_pks['id'] == user_feature.id }

      expect(confirmation).not_to be_nil
      expect(confirmation.attr_changes['enabled']).to eq(target ? 1 : 0)
    end

    it 'prevents users from updating other VPS features' do
      as(SpecSeed.user) { json_put update_path(other_vps.id, other_feature.id), feature: { enabled: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown feature id' do
      missing_id = VpsFeature.maximum(:id).to_i + 100

      as(SpecSeed.user) { json_put update_path(user_vps.id, missing_id), feature: { enabled: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'UpdateAll' do
    before do
      ensure_signer_unlocked!
    end

    it 'rejects unauthenticated access' do
      json_post update_all_path(user_vps.id), feature: { tun: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to update all features' do
      payload = {
        tun: false,
        fuse: false,
        kvm: false
      }

      as(SpecSeed.user) { json_post update_all_path(user_vps.id), feature: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      chain = TransactionChain.find(action_state_id)
      expect(chain.user_id).to eq(SpecSeed.user.id)
      expect(chain.type).to eq('TransactionChains::Vps::Features')
      expect(chain.name).to eq('features')
      expect(chain.state).to eq('queued')
      expect(chain.size).to eq(1)
      expect(chain.concern_type).to eq('chain_affect')
      expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['Vps', user_vps.id])

      transaction = chain.transactions.first
      expect(transaction.handle).to eq(8001)
      expect(transaction.vps_id).to eq(user_vps.id)

      confirmations = TransactionConfirmation.where(
        transaction_id: transaction.id,
        class_name: 'VpsFeature',
        confirm_type: :edit_after_type
      )
      expect(confirmations).not_to be_empty

      expect(ObjectHistory.where(tracked_object: user_vps, event_type: 'features').exists?).to be(true)
    end

    it 'prevents users from updating other VPS features' do
      as(SpecSeed.user) { json_post update_all_path(other_vps.id), feature: { tun: false } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update all features for any VPS' do
      as(SpecSeed.admin) { json_post update_all_path(other_vps.id), feature: { tun: false } }

      expect_status(200)
      expect(json['status']).to be(true)
    end
  end
end
