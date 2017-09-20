require 'spec_helper'

describe 'Vps.passwd' do
  use_version 1

  context 'logged as user01' do
    login('user01', 1234)

    it 'changes password to own VPS' do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user01').vpses.take!.id}/passwd"

      expect(api_response).to be_ok
    end

    it "does not change password to somebody else's VPS" do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user02').vpses.take!.id}/passwd"

      expect(api_response).to be_failed
    end
  end

  context 'logged as admin' do
    login('admin', '1234')

    it 'changes password to any VPS' do
      api :post, "/v1/vpses/#{Vps.take!.id}/passwd"

      expect(api_response).to be_ok
    end

    it 'returns password' do
      api :post, "/v1/vpses/#{Vps.take!.id}/passwd"

      expect(api_response[:vps][:password]).to be_an_instance_of(String)
      expect(api_response[:vps][:password].length).to eq(20)
    end
  end
end
