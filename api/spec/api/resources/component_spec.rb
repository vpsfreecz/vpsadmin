# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Component' do
  before do
    header 'Accept', 'application/json'

    Component.create!(name: 'spec_comp_a', label: 'Spec Comp A', description: 'A')
    Component.create!(name: 'spec_comp_b', label: 'Spec Comp B', description: 'B')
  end

  def index_path
    vpath('/components')
  end

  def show_path(id)
    vpath("/components/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def components
    json.dig('response', 'components')
  end

  def component
    json.dig('response', 'component')
  end

  describe 'Index' do
    it 'allows unauthenticated access' do
      json_get index_path

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
      arr = components
      expect(arr).to be_an(Array)
      names = arr.map { |row| row['name'] }
      expect(names).to include('spec_comp_a', 'spec_comp_b')

      row = arr.find { |item| item['name'] == 'spec_comp_a' }
      expect(row).to include('id', 'name', 'label', 'description')
      expect(row['label']).to eq('Spec Comp A')
      expect(row['description']).to eq('A')
    end

    it 'allows authenticated access' do
      as(SpecSeed.user) { json_get index_path }

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
      names = components.map { |row| row['name'] }
      expect(names).to include('spec_comp_a', 'spec_comp_b')
    end

    it 'supports limit pagination' do
      json_get index_path, component: { limit: 1 }

      expect(last_response.status).to eq(200)
      expect(components.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = Component.find_by!(name: 'spec_comp_a').id
      json_get index_path, component: { from_id: boundary }

      expect(last_response.status).to eq(200)
      ids = components.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      json_get index_path, _meta: { count: true }

      expect(last_response.status).to eq(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Component.count)
    end
  end

  describe 'Show' do
    it 'allows unauthenticated access' do
      id = Component.find_by!(name: 'spec_comp_a').id
      json_get show_path(id)

      expect(last_response.status).to eq(200)
      expect(json['status']).to be(true)
      expect(component['id']).to eq(id)
      expect(component['name']).to eq('spec_comp_a')
      expect(component['label']).to eq('Spec Comp A')
      expect(component['description']).to eq('A')
    end

    it 'allows authenticated access' do
      id = Component.find_by!(name: 'spec_comp_a').id
      as(SpecSeed.user) { json_get show_path(id) }

      expect(last_response.status).to eq(200)
      expect(component['id']).to eq(id)
      expect(component['name']).to eq('spec_comp_a')
    end

    it 'returns 404 for unknown component' do
      missing = Component.maximum(:id).to_i + 100
      json_get show_path(missing)

      expect(last_response.status).to eq(404)
      expect(json['status']).to be(false)
    end
  end
end
