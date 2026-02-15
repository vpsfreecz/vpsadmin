# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User' do
  before do
    header 'Accept', 'application/json'
  end

  def touch_path(id)
    vpath("/users/#{id}/touch")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  describe 'Touch' do
    it 'rejects unauthenticated access' do
      json_get touch_path(SpecSeed.user.id)

      expect(last_response.status).to be_in([401, 403])
      expect(json['status']).to be(false)
    end

    it 'allows normal user to touch themselves' do
      SpecSeed.user.update!(last_activity_at: Time.at(0))

      as(SpecSeed.user) { json_get touch_path(SpecSeed.user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(SpecSeed.user.reload.last_activity_at).not_to be_nil
      expect(SpecSeed.user.last_activity_at).to be > Time.at(0)
    end

    it 'forbids normal user touching a different user' do
      SpecSeed.other_user.update!(last_activity_at: Time.at(0))

      as(SpecSeed.user) { json_get touch_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('access denied')
      expect(SpecSeed.other_user.reload.last_activity_at).to eq(Time.at(0))
    end

    it 'allows admin to touch any user' do
      SpecSeed.other_user.update!(last_activity_at: Time.at(0))

      as(SpecSeed.admin) { json_get touch_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(SpecSeed.other_user.reload.last_activity_at).to be > Time.at(0)
    end

    it 'returns 404 for unknown user' do
      missing = User.maximum(:id).to_i + 10

      as(SpecSeed.admin) { json_get touch_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
