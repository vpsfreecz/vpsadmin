# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::NewsLog', requires_plugins: :newslog do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.support
    SpecSeed.admin
  end

  def index_path
    vpath('/news_logs')
  end

  def show_path(id)
    vpath("/news_logs/#{id}")
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

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def news_logs
    json.dig('response', 'news_logs')
  end

  def news_log
    json.dig('response', 'news_log') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  let(:timepoints) do
    {
      past_older: Time.now - 2.hours,
      past_recent: Time.now - 1.hour,
      future: Time.now + 2.hours
    }
  end

  let!(:news_fixtures) do
    {
      past_older: ::NewsLog.create!(message: 'Spec News Past 1', published_at: timepoints[:past_older]),
      past_recent: ::NewsLog.create!(message: 'Spec News Past 2', published_at: timepoints[:past_recent]),
      future: ::NewsLog.create!(message: 'Spec News Future', published_at: timepoints[:future])
    }
  end

  def time_past_older
    timepoints.fetch(:past_older)
  end

  def news_past_older
    news_fixtures.fetch(:past_older)
  end

  def news_past_recent
    news_fixtures.fetch(:past_recent)
  end

  def news_future
    news_fixtures.fetch(:future)
  end

  def payload_min
    { message: 'Spec News Created' }
  end

  describe 'API description' do
    it 'includes news_log endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'news_log#index',
        'news_log#show',
        'news_log#create',
        'news_log#update',
        'news_log#delete'
      )
    end
  end

  describe 'Index' do
    it 'allows unauthenticated access and returns published news only' do
      json_get index_path

      expect_status(200)
      expect(json['status']).to be(true)

      messages = news_logs.map { |row| row['message'] }
      expect(messages).to eq(['Spec News Past 2', 'Spec News Past 1'])
      expect(messages).not_to include('Spec News Future')

      expect(news_logs).to all(include('id', 'message', 'published_at', 'created_at', 'updated_at'))
    end

    it 'includes future news for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      messages = news_logs.map { |row| row['message'] }
      expect(messages).to eq(['Spec News Future', 'Spec News Past 2', 'Spec News Past 1'])
    end

    it 'supports since filter' do
      since = (time_past_older + 30.minutes).iso8601

      json_get index_path, news_log: { since: since }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(news_logs.map { |row| row['message'] }).to eq(['Spec News Past 2'])
    end

    it 'supports pagination limit' do
      json_get index_path, news_log: { limit: 1 }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(news_logs.length).to eq(1)
    end

    it 'returns meta count respecting visibility' do
      json_get index_path, _meta: { count: true }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(2)
    end
  end

  describe 'Show' do
    it 'allows unauthenticated access for published news' do
      json_get show_path(news_past_older.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(news_log).to include(
        'id' => news_past_older.id,
        'message' => 'Spec News Past 1'
      )
      expect(news_log['published_at']).not_to be_nil
    end

    it 'allows unauthenticated access for future news by id' do
      json_get show_path(news_future.id)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(news_log['message']).to eq('Spec News Future')
    end

    it 'returns 404 for unknown id' do
      missing = ::NewsLog.maximum(:id).to_i + 100

      json_get show_path(missing)

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, news_log: payload_min

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, news_log: payload_min }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post index_path, news_log: payload_min }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create with default published_at' do
      now = Time.now

      # rubocop:disable RSpec/ExpectChange
      expect do
        as(SpecSeed.admin) { json_post index_path, news_log: payload_min }
      end.to change { ::NewsLog.count }.by(1)
      # rubocop:enable RSpec/ExpectChange

      expect_status(200)
      expect(json['status']).to be(true)

      record = ::NewsLog.find(news_log['id'])
      expect(record.message).to eq(payload_min[:message])
      expect(record.published_at).to be_within(10).of(now)
    end

    it 'returns validation errors when message is missing' do
      as(SpecSeed.admin) { json_post index_path, news_log: { published_at: Time.now.iso8601 } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('message')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(news_past_older.id), news_log: { message: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(news_past_older.id), news_log: { message: 'Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(news_past_older.id), news_log: { message: 'Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update message and published_at' do
      new_message = 'Spec News Updated'
      new_time = Time.now - 5.minutes

      as(SpecSeed.admin) do
        json_put show_path(news_past_older.id), news_log: {
          message: new_message,
          published_at: new_time.iso8601
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(news_log['message']).to eq(new_message)

      record = ::NewsLog.find(news_past_older.id)
      expect(record.message).to eq(new_message)
      expect(record.published_at).to be_within(1).of(new_time)
    end

    it 'returns validation errors when message is missing' do
      as(SpecSeed.admin) do
        json_put show_path(news_past_older.id), news_log: { published_at: (Time.now - 5.minutes).iso8601 }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('message')
    end

    it 'returns 404 for unknown id' do
      missing = ::NewsLog.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_put show_path(missing), news_log: { message: 'x' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(news_past_older.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(news_past_older.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete show_path(news_past_older.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete news logs' do
      # rubocop:disable RSpec/ExpectChange
      expect do
        as(SpecSeed.admin) { json_delete show_path(news_past_recent.id) }
      end.to change { ::NewsLog.count }.by(-1)
      # rubocop:enable RSpec/ExpectChange

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown id' do
      missing = ::NewsLog.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
