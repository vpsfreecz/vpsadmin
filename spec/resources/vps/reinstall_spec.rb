require 'spec_helper'

describe 'Vps.reinstall' do
  use_version 1

  context 'logged as user01' do
    login('user01', 1234)

    it 'reinstalls own VPS' do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user01').vpses.take.id}/reinstall", {
          vps: {
              os_template: OsTemplate.take!.id
          }
      }

      expect(api_response).to be_ok
    end

    it "does not reinstalls somebody else's VPS" do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user02').vpses.take.id}/reinstall", {
          vps: {
              os_template: OsTemplate.take!.id
          }
      }

      expect(api_response).to be_failed
    end
  end

  context 'logged as admin' do
    login('admin', '1234')

    it 'reinstalls any VPS' do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user01').vpses.take.id}/reinstall", {
          vps: {
              os_template: OsTemplate.take!.id
          }
      }

      expect(api_response).to be_ok
    end

    it 'does not reinstall with invalid template' do
      api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user01').vpses.take.id}/reinstall", {
          vps: {
              os_template: 9999
          }
      }

      expect(api_response).to be_failed
    end
  end
end
