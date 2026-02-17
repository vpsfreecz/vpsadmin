# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::HelpBox', requires_plugins: :webui do
  before do
    header 'Accept', 'application/json'
  end

  let(:admin) { SpecSeed.admin }
  let(:user) { SpecSeed.user }

  let!(:fixtures) do
    HelpBox.delete_all

    lang_en = SpecSeed.language
    lang_cs = Language.find_or_create_by!(code: 'cs') { |lang| lang.label = 'Czech' }

    b1 = HelpBox.create!(page: 'dashboard', action: 'show', language: lang_en, content: 'Box 1', order: 10)
    b2 = HelpBox.create!(page: 'dashboard', action: '*', language: lang_en, content: 'Box 2', order: 20)
    b3 = HelpBox.create!(page: '*', action: '*', language: lang_en, content: 'Box 3', order: 30)
    b4 = HelpBox.create!(page: '*', action: 'show', language: lang_en, content: 'Box 4', order: 40)
    b5 = HelpBox.create!(page: 'other', action: 'show', language: lang_en, content: 'Box 5', order: 50)
    b6 = HelpBox.create!(page: 'dashboard', action: 'show', language: lang_cs, content: 'Box 6', order: 60)
    b7 = HelpBox.create!(page: 'dashboard', action: 'show', language: nil, content: 'Box 7', order: 70)

    {
      lang_en: lang_en,
      lang_cs: lang_cs,
      b1: b1,
      b2: b2,
      b3: b3,
      b4: b4,
      b5: b5,
      b6: b6,
      b7: b7
    }
  end

  def index_path
    vpath('/help_boxes')
  end

  def show_path(id)
    vpath("/help_boxes/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
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

  def help_boxes
    json.dig('response', 'help_boxes') || []
  end

  def help_box
    json.dig('response', 'help_box') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def lang_en
    fixtures.fetch(:lang_en)
  end

  def lang_cs
    fixtures.fetch(:lang_cs)
  end

  def b1
    fixtures.fetch(:b1)
  end

  def b2
    fixtures.fetch(:b2)
  end

  def b3
    fixtures.fetch(:b3)
  end

  def b4
    fixtures.fetch(:b4)
  end

  def b5
    fixtures.fetch(:b5)
  end

  def b6
    fixtures.fetch(:b6)
  end

  def b7
    fixtures.fetch(:b7)
  end

  describe 'Index' do
    it 'allows unauthenticated access' do
      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)
      expect(help_boxes).to be_an(Array)
      expect(help_boxes.length).to eq(HelpBox.count)
    end

    it 'does not apply wildcard matching by default' do
      json_get index_path, help_box: { page: 'dashboard', action: 'show' }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = help_boxes.map { |row| row['id'] }
      expect(ids).to contain_exactly(b1.id, b6.id, b7.id)
    end

    it 'applies wildcard matching when view=true' do
      json_get index_path, help_box: { view: true, page: 'dashboard', action: 'show' }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = help_boxes.map { |row| row['id'] }
      expect(ids).to eq([b1.id, b2.id, b3.id, b4.id, b7.id])
    end

    it 'includes NULL-language boxes when view=true without explicit language' do
      json_get index_path, help_box: { view: true, page: 'dashboard', action: 'show' }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = help_boxes.map { |row| row['id'] }
      expect(ids).to include(b7.id)
    end

    it 'filters to explicit language when view=true and language provided' do
      json_get index_path, help_box: { view: true, language: lang_cs.id }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = help_boxes.map { |row| row['id'] }
      expect(ids).to contain_exactly(b6.id)
      expect(ids).not_to include(b7.id)
    end

    it 'returns total_count when requested' do
      json_get index_path, _meta: { count: true }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(HelpBox.count)
    end
  end

  describe 'Show' do
    it 'allows unauthenticated access' do
      json_get show_path(b1.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(help_box['id']).to eq(b1.id)
      expect(help_box).to include(
        'page' => b1.page,
        'action' => b1.action,
        'content' => b1.content,
        'order' => b1.order
      )
      expect(rid(help_box['language'])).to eq(b1.language_id)
    end

    it 'returns 404 for unknown id' do
      missing = HelpBox.maximum(:id).to_i + 100

      json_get show_path(missing)

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, help_box: { page: 'x', action: 'y', content: 'z' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post index_path, help_box: { page: 'x', action: 'y', content: 'z' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create help boxes' do
      as(admin) do
        json_post index_path, help_box: {
          page: 'new',
          action: 'show',
          language: lang_cs.id,
          content: 'Created',
          order: 123
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(help_box).to include(
        'page' => 'new',
        'action' => 'show',
        'content' => 'Created',
        'order' => 123
      )
      expect(rid(help_box['language'])).to eq(lang_cs.id)

      created_id = help_box['id']
      record = HelpBox.find(created_id)
      expect(record.page).to eq('new')
      expect(record.action).to eq('show')
      expect(record.language_id).to eq(lang_cs.id)
      expect(record.content).to eq('Created')
      expect(record.order).to eq(123)
    end

    it 'returns validation errors for admins' do
      as(admin) { json_post index_path, help_box: { page: 'x', action: 'y', content: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('content')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(b1.id), help_box: { content: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put show_path(b1.id), help_box: { content: 'Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update help boxes' do
      as(admin) { json_put show_path(b1.id), help_box: { content: 'Updated', order: 5 } }

      expect_status(200)
      expect(json['status']).to be(true)

      record = HelpBox.find(b1.id)
      expect(record.content).to eq('Updated')
      expect(record.order).to eq(5)
    end

    it 'returns validation errors for admins' do
      as(admin) { json_put show_path(b1.id), help_box: { content: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('content')
    end

    it 'returns 404 for unknown id' do
      missing = HelpBox.maximum(:id).to_i + 100

      as(admin) { json_put show_path(missing), help_box: { content: 'Updated' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(b1.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete show_path(b1.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete help boxes' do
      as(admin) { json_delete show_path(b1.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(HelpBox.find_by(id: b1.id)).to be_nil
    end

    it 'returns 404 for unknown id' do
      missing = HelpBox.maximum(:id).to_i + 100

      as(admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
