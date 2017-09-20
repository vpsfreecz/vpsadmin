require 'spec_helper'

%w(start stop restart).each do |action|
  describe "Vps.#{action}" do
    use_version 1

    context 'logged as user01' do
      login('user01', 1234)

      it "#{action}s own VPS" do
        api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user01').vpses.take.id}/#{action}"

        expect(api_response).to be_ok
      end

      it "does not #{action} somebody else's VPS" do
        api :post, "/v1/vpses/#{User.find_by!(m_nick: 'user02').vpses.take.id}/#{action}"

        expect(api_response).to be_failed
      end
    end
  end
end
