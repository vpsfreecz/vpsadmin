# frozen_string_literal: true

RSpec.describe ApiAppHelper do
  describe 'Stability' do
    before do
      header 'Accept', 'application/json'
    end

    def json_get(path)
      get path, nil, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end

    it 'handles repeated root responses' do
      2.times do
        options '/'
        message = "Expected / to respond, got #{last_response.status} body=#{last_response.body}"
        expect(last_response.status).to eq(200), message
      end
    end

    it 'handles repeated authenticated current-user responses' do
      path = vpath('/users/current')

      2.times do
        as(SpecSeed.user) { json_get path }
        message = "Expected #{path} to respond, got #{last_response.status} body=#{last_response.body}"
        expect(last_response.status).to eq(200), message
      end
    end
  end
end
