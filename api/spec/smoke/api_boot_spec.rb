# frozen_string_literal: true

require 'json'

RSpec.describe ApiAppHelper do
  it 'responds to OPTIONS / with JSON' do
    header 'Accept', 'application/json'
    options '/'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('application/json')

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Hash)
    expect(body['response']).to be_a(Hash)
  end
end
