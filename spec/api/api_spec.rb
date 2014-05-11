require_relative '../spec_helper'

describe 'The API' do
  it 'responds to GET /' do
    get '/'
    expect(last_response).to be_ok
  end

  it 'responds to OPTIONS /' do
    options '/'
    expect(last_response).to be_ok
  end

  VpsAdmin::API.get_versions.each do |v|
    it "responds to GET /v#{v}/" do
      get "/v#{v}/"
      expect(last_response).to be_ok
    end

    it "responds to OPTIONS /v#{v}/" do
      options "/v#{v}/"
      expect(last_response).to be_ok
    end
  end
end
