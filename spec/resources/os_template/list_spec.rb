require 'spec_helper'

describe 'OsTemplate.list' do
  use_version 1

  context 'as unauthenticated user' do
    it 'does not list OS templates' do
      api :get, '/v1/os_templates'

      expect(api_response).to be_failed
    end
  end

  context 'logged as user' do
    login('user01', '1234')

    it 'lists OS templates' do
      api :get, '/v1/os_templates'

      expect(api_response).to be_ok
      expect(api_response[:os_templates]).to be_an_instance_of(Array)
    end

    it 'does not return enabled' do
      api :get, '/v1/os_templates'

      expect(api_response[:os_templates].first[:enabled]).to be_nil
    end
  end

  context 'logged as admin' do
    login('admin', '1234')

    it 'returns enabled' do
      api :get, '/v1/os_templates'

      expect([1,0]).to include(api_response[:os_templates].first[:enabled])
    end
  end
end
