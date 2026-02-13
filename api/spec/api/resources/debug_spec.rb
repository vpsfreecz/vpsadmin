# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Debug' do
  before do
    header 'Accept', 'application/json'
  end

  def list_object_counts_path
    vpath('/debugs/list_object_counts')
  end

  def hash_top_path
    vpath('/debugs/hash_top')
  end

  def array_top_path
    vpath('/debugs/array_top')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def response_list
    json.dig('response', 'debugs')
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def stub_objectspace(objects)
    original = ObjectSpace.method(:each_object)

    allow(ObjectSpace).to receive(:each_object) do |*args, &blk|
      if args.empty?
        blk ? objects.each(&blk) : objects.each
      else
        original.call(*args, &blk)
      end
    end
  end

  describe 'API description' do
    it 'includes debug endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'debug#list_object_counts',
        'debug#hash_top',
        'debug#array_top'
      )
    end
  end

  describe 'List object counts' do
    it 'rejects unauthenticated access' do
      json_get list_object_counts_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get list_object_counts_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get list_object_counts_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows object counts for admin' do
      objects = ['a', 'b', 'c', {}, {}, []]
      stub_objectspace(objects)

      as(SpecSeed.admin) { json_get list_object_counts_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_list).to be_a(Array)
      expect(response_list.size).to eq(3)

      expect(response_list[0]['object']).to eq('String')
      expect(response_list[0]['count']).to eq(3)
      expect(response_list[1]['object']).to eq('Hash')
      expect(response_list[1]['count']).to eq(2)
      expect(response_list[2]['object']).to eq('Array')
      expect(response_list[2]['count']).to eq(1)

      counts = response_list.map { |row| row['count'] }
      expect(counts).to eq(counts.sort.reverse)
    end
  end

  describe 'Hash top' do
    it 'rejects unauthenticated access' do
      json_get hash_top_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get hash_top_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get hash_top_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists the largest hashes for admin' do
      h1 = { 'k1' => 1 }

      h2 = {}
      1.upto(50) { |i| h2["k#{i}"] = i }

      h3 = {}
      1.upto(100) { |i| h3["k#{i}"] = i }

      stub_objectspace([h1, h2, h3, 'not-a-hash', []])

      as(SpecSeed.admin) { json_get hash_top_path, debug: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_list).to be_a(Array)
      expect(response_list.size).to eq(2)

      expect(response_list[0]['size']).to eq(100)
      expect(response_list[1]['size']).to eq(50)

      response_list.each do |row|
        expect(row.keys).to include('size', 'sample')
        expect(row['sample']).to be_a(Hash)
        expect(row['sample'].keys.size).to be <= 5
      end

      expect(response_list[0]['sample']).to include('k1')
      expect(response_list[0]['sample']['k1']).to be_a(String)
    end

    it 'coerces non-numeric limit to zero' do
      h1 = { 'k1' => 1 }
      h2 = { 'k1' => 1, 'k2' => 2 }

      stub_objectspace([h1, h2, 'not-a-hash'])

      as(SpecSeed.admin) { json_get hash_top_path, debug: { limit: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_list).to be_a(Array)
      expect(response_list.size).to eq(1)
      expect(response_list[0]['size']).to eq(2)
    end
  end

  describe 'Array top' do
    it 'rejects unauthenticated access' do
      json_get array_top_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get array_top_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get array_top_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists the largest arrays for admin' do
      a1 = [1]
      a2 = (1..50).to_a
      a3 = (1..100).to_a

      stub_objectspace([a1, a2, a3, {}, 'not-an-array'])

      as(SpecSeed.admin) { json_get array_top_path, debug: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_list).to be_a(Array)
      expect(response_list.size).to eq(2)

      expect(response_list[0]['size']).to eq(100)
      expect(response_list[1]['size']).to eq(50)

      response_list.each do |row|
        expect(row.keys).to include('size', 'sample')
        expect(row['sample']).to be_a(Array)
        expect(row['sample'].size).to be <= 5
      end

      expect(response_list[0]['sample'].first).to eq('1')
    end

    it 'coerces non-numeric limit to zero' do
      a1 = [1]
      a2 = [1, 2]

      stub_objectspace([a1, a2, 'not-an-array'])

      as(SpecSeed.admin) { json_get array_top_path, debug: { limit: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_list).to be_a(Array)
      expect(response_list.size).to eq(1)
      expect(response_list[0]['size']).to eq(2)
    end
  end
end
