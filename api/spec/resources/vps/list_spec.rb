require 'spec_helper'

describe 'Vps.index' do
  use_version 1

  context 'unauthenticated' do
    it 'does not allow to list VPS' do
      get '/v1/vpses'
      expect(last_response.status).to be(401)
    end
  end

  context 'authenticated as admin' do
    login('admin', '1234')

    it 'returns a list of all VPSes' do
      get '/v1/vpses'

      expect(last_response).to be_ok
      expect(api_response[:vpses].count).to eq(Vps.count)
    end
  end

  context 'authenticated as user01' do
    login('user01', '1234')

    it 'returns a list of VPSes owned by user01' do
      get '/v1/vpses'

      expect(last_response).to be_ok

      user = User.find_by!(m_nick: 'user01')

      api_response[:vpses].each do |vps|
        expect(Vps.find(vps[:id]).m_id).to eq(user.id)
      end
    end
  end
end
