# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Language' do
  before do
    header 'Accept', 'application/json'

    Language.find_or_create_by!(code: 'aa') { |language| language.label = 'Lang AA' }
    Language.find_or_create_by!(code: 'bb') { |language| language.label = 'Lang BB' }
  end

  def index_path
    vpath('/languages')
  end

  def show_path(id)
    vpath("/languages/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def languages
    json.dig('response', 'languages')
  end

  def language
    json.dig('response', 'language')
  end

  describe 'Index' do
    it 'allows unauthenticated access' do
      json_get index_path

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
    end

    it 'allows users to list languages' do
      as(SpecSeed.user) { json_get index_path }

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
      arr = languages
      expect(arr).to be_an(Array)
      codes = arr.map { |lang| lang['code'] }
      expect(codes).to include('aa', 'bb')
    end

    it 'allows admins to list languages' do
      as(SpecSeed.admin) { json_get index_path }

      expect(last_response.status).to eq(200)
      codes = languages.map { |lang| lang['code'] }
      expect(codes).to include('aa', 'bb')
    end

    it 'supports limit pagination' do
      as(SpecSeed.user) { json_get index_path, language: { limit: 1 } }

      expect(last_response.status).to eq(200)
      expect(languages.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Language.find_by!(code: 'aa').id
      as(SpecSeed.user) { json_get index_path, language: { from_id: boundary } }

      expect(last_response.status).to eq(200)
      ids = languages.map { |lang| lang['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.user) { json_get index_path, _meta: { count: true } }

      expect(last_response.status).to eq(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Language.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      id = Language.find_by!(code: 'aa').id
      json_get show_path(id)

      expect(last_response.status).to eq(401)
      expect(json['status']).to be(false)
    end

    it 'shows a language for users' do
      id = Language.find_by!(code: 'aa').id
      as(SpecSeed.user) { json_get show_path(id) }

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
      expect(language['id']).to eq(id)
      expect(language['code']).to eq('aa')
      expect(language['label']).to eq('Lang AA')
    end

    it 'allows admins to show a language' do
      id = Language.find_by!(code: 'aa').id
      as(SpecSeed.admin) { json_get show_path(id) }

      expect(last_response.status).to eq(200)
    end

    it 'returns 404 for unknown language' do
      missing = Language.maximum(:id).to_i + 10
      as(SpecSeed.user) { json_get show_path(missing) }

      expect(last_response.status).to eq(404)
      expect(json['status']).to be(false)
    end
  end
end
