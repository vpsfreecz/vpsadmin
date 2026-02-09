# frozen_string_literal: true

RSpec.describe ApiAppHelper do
  describe 'Auth smoke' do
    let(:path) { vpath('/users/current') }

    before do
      header 'Accept', 'application/json'
    end

    def json_get(path)
      get path, nil, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end

    it 'rejects unauthenticated access' do
      json_get path
      expect(last_response.status).to be_in([401, 403])
    end

    it 'returns current user for normal user' do
      as(SpecSeed.user) { json_get path }

      message = "Expected #{path} to respond, got #{last_response.status} body=#{last_response.body}"
      expect(last_response.status).to eq(200), message
      body = json
      expect(body['status']).to be(true)

      login =
        body.dig('response', 'login') ||
        body.dig('response', 'user', 'login')

      expect(login).to eq('user')
    end

    it 'returns current user for admin' do
      as(SpecSeed.admin) { json_get path }

      message = "Expected #{path} to respond, got #{last_response.status} body=#{last_response.body}"
      expect(last_response.status).to eq(200), message
      body = json
      expect(body['status']).to be(true)

      login =
        body.dig('response', 'login') ||
        body.dig('response', 'user', 'login')

      expect(login).to eq('admin')
    end
  end
end
