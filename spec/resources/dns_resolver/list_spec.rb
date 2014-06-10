require 'spec_helper'

shared_examples :does_not_list do
  it 'does not list DNS resolvers' do
    api :get, '/v1/dns_resolvers'
    expect(api_response).to be_failed
  end
end

shared_examples :does_list do
  it 'lists DNS resolvers' do
    api :get, '/v1/dns_resolvers'
    expect(api_response).to be_ok
  end
end

describe 'DnsResolver.index' do
  use_version 1

  context 'as unauthenticated user' do
    include_examples :does_not_list
  end

  context 'logged as user' do
    login('user01', 1234)

    include_examples :does_list
  end

  context 'logged as admin' do
    login('admin', '1234')

    include_examples :does_list
  end
end
