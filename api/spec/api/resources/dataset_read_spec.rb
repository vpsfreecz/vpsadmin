# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Dataset read actions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.node
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  let(:pool) do
    SpecSeed.pool.tap do |p|
      p.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }

  let!(:user_data) do
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "spec-user-ds-#{SecureRandom.hex(4)}"
    )
  end

  let!(:other_data) do
    create_dataset_with_pool!(
      user: other_user,
      pool: pool,
      name: "spec-other-ds-#{SecureRandom.hex(4)}"
    )
  end

  let(:user_dataset) { user_data.first }
  let(:other_dataset) { other_data.first }

  def datasets_path
    vpath('/datasets')
  end

  def dataset_path(id)
    vpath("/datasets/#{id}")
  end

  def find_by_name_path
    vpath('/datasets/find_by_name')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def datasets
    json.dig('response', 'datasets') || []
  end

  def dataset_obj
    json.dig('response', 'dataset') || json['dataset'] || json['response']
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get datasets_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns only user datasets and hides sharenfs' do
      as(user) { json_get datasets_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = datasets.map { |row| row['id'] }
      expect(ids).to include(user_dataset.id)
      expect(ids).not_to include(other_dataset.id)

      row = datasets.find { |r| r['id'] == user_dataset.id }
      expect(row).not_to have_key('sharenfs')
    end

    it 'ignores user filter for non-admin' do
      as(user) { json_get datasets_path, dataset: { user: other_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = datasets.map { |row| row['id'] }
      expect(ids).to include(user_dataset.id)
      expect(ids).not_to include(other_dataset.id)
    end

    it 'allows admin to filter by user and includes sharenfs' do
      as(SpecSeed.admin) { json_get datasets_path, dataset: { user: user.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = datasets.map { |row| row['id'] }
      expect(ids).to include(user_dataset.id)
      expect(ids).not_to include(other_dataset.id)

      row = datasets.find { |r| r['id'] == user_dataset.id }
      expect(row).to have_key('sharenfs')
    end

    it 'filters by vps when nil' do
      ds_with_vps, dip_with_vps = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "spec-vps-ds-#{SecureRandom.hex(4)}"
      )

      vps = Vps.new(
        user: user,
        node: SpecSeed.node,
        hostname: "spec-ds-vps-#{SecureRandom.hex(4)}",
        os_template: SpecSeed.os_template,
        dns_resolver: SpecSeed.dns_resolver,
        dataset_in_pool: dip_with_vps,
        object_state: :active,
        confirmed: :confirmed
      )

      with_current_user(SpecSeed.admin) do
        vps.save!
      end

      ds_with_vps.update!(vps: vps)

      as(SpecSeed.admin) { json_get datasets_path, dataset: { vps: nil } }

      expect_status(200)
      ids = datasets.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_dataset.id, other_dataset.id)
    end

    it 'supports subtree filter' do
      root, = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "spec-root-#{SecureRandom.hex(4)}"
      )
      child, = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "child-#{SecureRandom.hex(3)}",
        parent: root
      )

      as(user) { json_get datasets_path, dataset: { dataset: root.id } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = datasets.map { |row| row['id'] }
      expect(ids).to contain_exactly(root.id, child.id)
    end

    it 'supports to_depth filter' do
      root, = create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "spec-depth-root-#{SecureRandom.hex(4)}"
      )
      create_dataset_with_pool!(
        user: user,
        pool: pool,
        name: "depth-child-#{SecureRandom.hex(3)}",
        parent: root
      )

      as(user) { json_get datasets_path, dataset: { dataset: root.id, to_depth: 0 } }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = datasets.map { |row| row['id'] }
      expect(ids).to contain_exactly(root.id)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get dataset_path(user_dataset.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to show own dataset and hides sharenfs' do
      as(user) { json_get dataset_path(user_dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dataset_obj['id']).to eq(user_dataset.id)
      expect(dataset_obj).not_to have_key('sharenfs')
    end

    it 'returns 404 for other user' do
      as(user) { json_get dataset_path(other_dataset.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show dataset and includes sharenfs' do
      as(SpecSeed.admin) { json_get dataset_path(other_dataset.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dataset_obj['id']).to eq(other_dataset.id)
      expect(dataset_obj).to have_key('sharenfs')
    end

    it 'returns 404 for unknown id' do
      missing = Dataset.maximum(:id).to_i + 10
      as(SpecSeed.admin) { json_get dataset_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Find by name' do
    it 'rejects unauthenticated access' do
      json_get find_by_name_path, dataset: { name: user_dataset.full_name }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to find own dataset' do
      as(user) { json_get find_by_name_path, dataset: { name: user_dataset.full_name } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dataset_obj['id']).to eq(user_dataset.id)
    end

    it 'does not allow user to find other user dataset' do
      as(user) do
        json_get find_by_name_path, dataset: { name: other_dataset.full_name, user: other_user.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/dataset not found/i)
    end

    it 'allows admin to find dataset for another user' do
      as(SpecSeed.admin) do
        json_get find_by_name_path, dataset: { name: other_dataset.full_name, user: other_user.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(dataset_obj['id']).to eq(other_dataset.id)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
