require_relative '../../spec_helper'

describe 'Vps.create' do
  use_version 1

  context 'as unauthenticated user' do
    it 'does not create a VPS' do
      post '/v1/vpses', {vps: {
          hostname: 'justatest',
          template_id: OsTemplate.take!.id,
          dns_resolver_id: DnsResolver.take!.id
      }}

      expect(last_response.status).to eq(401)
    end
  end

  context 'authenticated' do
    context 'as user with no privileges' do
      login('user01', '1234')

      it 'creates a VPS' do
        # FIXME - not implemented
      end
    end

    context 'as admin' do
      login('admin', '1234')

      it 'creates a VPS' do
        api :post, '/v1/vpses', {vps: {
            user_id: User.take!.id,
            hostname: 'justatest',
            template_id: OsTemplate.take!.id,
            dns_resolver_id: DnsResolver.take!.id,
            node_id: Node.take!.id,
        }}

        expect(api_response).to be_ok
      end

      it 'does not create VPS for non-existing user' do
        api :post, '/v1/vpses', {vps: {
            user_id: 9999,
            hostname: 'justatest',
            template_id: OsTemplate.take!.id,
            dns_resolver_id: DnsResolver.take!.id,
            node_id: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing node' do
        api :post, '/v1/vpses', {vps: {
            user_id: User.take!.id,
            hostname: 'justatest',
            template_id: OsTemplate.take!.id,
            dns_resolver_id: DnsResolver.take!.id,
            node_id: 9999,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing OS template' do
        api :post, '/v1/vpses', {vps: {
            user_id: User.take!.id,
            hostname: 'justatest',
            template_id: 9999,
            dns_resolver_id: DnsResolver.take!.id,
            node_id: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing DNS resolver' do
        api :post, '/v1/vpses', {vps: {
            user_id: User.take!.id,
            hostname: 'justatest',
            template_id: OsTemplate.take!.id,
            dns_resolver_id: 9999,
            node_id: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end
    end
  end
end
