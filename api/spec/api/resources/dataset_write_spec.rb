# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Dataset write actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
  end

  let(:pool) do
    SpecSeed.pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:other_pool) do
    SpecSeed.other_pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }

  let(:root_name) { "root-#{SecureRandom.hex(4)}" }

  let!(:root_data) do
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: root_name,
      label: root_name
    )
  end

  let(:root_dataset) { root_data.first }
  let(:root_dip) { root_data.last }

  def datasets_path
    vpath('/datasets')
  end

  def dataset_path(id)
    vpath("/datasets/#{id}")
  end

  def inherit_path(id)
    vpath("/datasets/#{id}/inherit")
  end

  def migrate_path(id)
    vpath("/datasets/#{id}/migrate")
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

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def dataset_obj
    json.dig('response', 'dataset') || json['dataset'] || json['response']
  end

  def response_message
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

  def create_session_for(user, ip: '192.0.2.88', user_agent: 'SpecUA/DatasetMigrate')
    UserSession.create!(
      user: user,
      auth_type: 'basic',
      api_ip_addr: ip,
      client_ip_addr: ip,
      user_agent: UserAgent.find_or_create!(user_agent),
      client_version: user_agent,
      scope: ['all'],
      label: 'Spec Dataset Migrate',
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  def create_stub_chain(user:)
    TransactionChain.create!(
      name: 'dataset_migrate',
      type: 'TransactionChain',
      state: :queued,
      size: 1,
      progress: 0,
      concern_type: :chain_affect,
      user: user,
      user_session: create_session_for(user)
    )
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post datasets_path, dataset: { name: "#{root_name}/child", automount: false }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create child dataset under labeled root' do
      ensure_signer_unlocked!

      as(user) do
        json_post datasets_path, dataset: { name: "#{root_name}/child", automount: false }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(TransactionChain.where(id: action_state_id).exists?).to be(true)

      full_name = dataset_obj['full_name'] || dataset_obj['name']
      expect(full_name).to end_with('/child')
      expect(dataset_obj).not_to have_key('sharenfs')
      expect(Dataset.where(full_name: "#{root_name}/child", user: user).exists?).to be(true)
    end

    it 'fails when root label does not exist' do
      as(user) do
        json_post datasets_path, dataset: { name: "missing-#{SecureRandom.hex(3)}/child" }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/dataset label/i)
    end

    it 'fails when dataset already exists' do
      create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: 'child',
        parent: root_dataset
      )

      as(user) do
        json_post datasets_path, dataset: { name: "#{root_name}/child", automount: false }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/already exists/i)
    end

    it 'denies create when parent dataset is not user-creatable' do
      root_dataset.update!(user_create: false)

      as(user) do
        json_post datasets_path, dataset: { dataset: root_dataset.id, name: 'child' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'denies create inside other user dataset using explicit parent' do
      other_parent, = create_dataset_with_pool!(
        user: other_user,
        pool: pool,
        name: "other-root-#{SecureRandom.hex(3)}"
      )

      as(user) do
        json_post datasets_path, dataset: { dataset: other_parent.id, name: 'child' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/insufficient permission/i)
    end

    it 'allows admin to create and set sharenfs' do
      ensure_signer_unlocked!

      as(admin) do
        json_post datasets_path, dataset: { dataset: root_dataset.id, name: 'adminchild', sharenfs: 'on' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dataset_obj['sharenfs']).to eq('on')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put dataset_path(root_dataset.id), dataset: { atime: true }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to update editable property' do
      ensure_signer_unlocked!

      as(user) do
        json_put dataset_path(root_dataset.id), dataset: { atime: true }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(Transaction.where(transaction_chain_id: action_state_id).exists?).to be(true)
    end

    it 'denies update when dataset is not editable' do
      root_dataset.update!(user_editable: false)

      as(user) do
        json_put dataset_path(root_dataset.id), dataset: { atime: true }
      end

      expect_status(200)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update even if dataset is not editable' do
      root_dataset.update!(user_editable: false)
      ensure_signer_unlocked!

      as(admin) do
        json_put dataset_path(root_dataset.id), dataset: { atime: true }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end

    it 'returns validation error for invalid property value' do
      as(user) do
        json_put dataset_path(root_dataset.id), dataset: { recordsize: 123 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/property invalid: recordsize/i)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete dataset_path(root_dataset.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'denies deletion when user_destroy is false' do
      root_dataset.update!(user_destroy: false)

      as(user) { json_delete dataset_path(root_dataset.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/insufficient permission/i)
    end

    it 'allows user to delete a simple dataset' do
      ensure_signer_unlocked!

      target, = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "delete-#{SecureRandom.hex(3)}"
      )

      as(user) { json_delete dataset_path(target.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(target.reload.confirmed).to eq(:confirm_destroy)
    end
  end

  describe 'Inherit' do
    it 'rejects unauthenticated access' do
      json_post inherit_path(root_dataset.id), dataset: { property: 'atime' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to inherit overridden property' do
      ensure_signer_unlocked!
      prop = root_dataset.dataset_properties.find_by!(name: 'atime')
      prop.update!(inherited: false)

      as(user) do
        json_post inherit_path(root_dataset.id), dataset: { property: 'atime' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end

    it 'returns error for invalid property name' do
      as(user) do
        json_post inherit_path(root_dataset.id), dataset: { property: 'doesnotexist' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/property does not exist/i)
    end

    it 'returns error for non-inheritable property' do
      as(user) do
        json_post inherit_path(root_dataset.id), dataset: { property: 'quota' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/not inheritable/i)
    end

    it 'denies user when dataset is not editable' do
      root_dataset.update!(user_editable: false)

      as(user) do
        json_post inherit_path(root_dataset.id), dataset: { property: 'atime' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/insufficient permission/i)
    end

    it 'allows admin to inherit even if dataset is not editable' do
      root_dataset.update!(user_editable: false)
      ensure_signer_unlocked!

      as(admin) do
        json_post inherit_path(root_dataset.id), dataset: { property: 'atime' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
    end
  end

  describe 'Migrate' do
    it 'forbids non-admin users' do
      as(user) { json_post migrate_path(root_dataset.id), dataset: { pool: other_pool.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'succeeds for admin with stubbed chain' do
      stub_chain = create_stub_chain(user: admin)
      src_dip = root_dip
      dst_pool = other_pool

      allow(TransactionChains::Dataset::Migrate).to receive(:fire2)
        .and_return([stub_chain, nil])

      as(admin) do
        json_post migrate_path(root_dataset.id), dataset: { pool: dst_pool.id, rsync: true }
      end

      expect(TransactionChains::Dataset::Migrate).to have_received(:fire2).with(
        args: [src_dip, dst_pool],
        kwargs: hash_including(rsync: true)
      )
      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to eq(stub_chain.id)
    end

    it 'rejects migration to the same pool' do
      as(admin) { json_post migrate_path(root_dataset.id), dataset: { pool: pool.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/already is on this pool/i)
    end

    it 'rejects migration for non-top-level datasets' do
      child, = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "child-#{SecureRandom.hex(3)}",
        parent: root_dataset
      )

      as(admin) { json_post migrate_path(child.id), dataset: { pool: other_pool.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/only top-level datasets can be migrated/i)
    end

    it 'rejects migration when source pool is not primary' do
      pool.update!(role: Pool.roles[:hypervisor])
      other_pool.update!(role: Pool.roles[:primary])

      as(admin) { json_post migrate_path(root_dataset.id), dataset: { pool: other_pool.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/source pool is not primary/i)
    end

    it 'rejects migration when destination pool is not primary' do
      pool.update!(role: Pool.roles[:primary])
      other_pool.update!(role: Pool.roles[:hypervisor])

      as(admin) { json_post migrate_path(root_dataset.id), dataset: { pool: other_pool.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/target pool is not primary/i)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
