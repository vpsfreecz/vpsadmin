require_relative '../../spec_helper'

shared_examples :does_not_create do
  before(:all) do
    @params = { user: {
        login: 'mynewuser',
        level: 1,
      }
    }
  end

  it 'does not create user' do
    api :post, '/v1/users', @params
    expect(api_response).to be_failed
  end
end

describe 'User.create' do
  use_version 1

  context 'as unauthenticated user' do
    include_examples :does_not_create
  end

  context 'logged as user' do
    login('user01', '1234')

    include_examples :does_not_create
  end

  context 'logged as admin' do
    login('admin', '1234')

    it 'creates new user' do
      api :post, '/v1/users', {user: {
          login: 'mynewuser',
          level: 1
        }
      }

      expect(api_response).to be_ok
      expect(api_response[:user][:id]).to be > 1
    end

    it 'does not create user with duplicit name' do
      api :post, '/v1/users', {user: {
          login: 'user01',
          level: 1
        }
      }

      expect(api_response).to be_failed
      expect(api_response.errors[:login]).to be_an_instance_of(Array)
    end
  end
end
