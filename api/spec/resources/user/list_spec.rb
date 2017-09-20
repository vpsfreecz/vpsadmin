require 'spec_helper'

shared_examples :does_not_list do
  it 'does not list users' do
    api :get, '/v1/users'
    expect(api_response).to be_failed
  end
end

describe 'User.index' do
  use_version 1

  context 'as unauthenticated user' do
    include_examples :does_not_list
  end

  context 'logged as user' do
    login('user01', 1234)

    include_examples :does_not_list
  end

  context 'logged as admin' do
    login('admin', '1234')

    it 'returns a list of users' do
      api :get, '/v1/users'

      expect(api_response).to be_ok
      expect(api_response[:users]).to be_an_instance_of(Array)
      expect(api_response[:users].count).to eq(3)
    end
  end
end
