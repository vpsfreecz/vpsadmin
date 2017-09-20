require 'spec_helper'

describe 'Vps.create' do
  use_version 1

  context 'as unauthenticated user' do
    it 'does not create a VPS' do
      post '/v1/vpses', {vps: {
          hostname: 'justatest',
          os_template: OsTemplate.take!.id,
          dns_resolver: DnsResolver.take!.id
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
            user: User.take!.id,
            hostname: 'justatest',
            os_template: OsTemplate.take!.id,
            dns_resolver: DnsResolver.take!.id,
            node: Node.take!.id,
        }}

        expect(api_response).to be_ok
      end

      it 'does not create VPS for non-existing user' do
        api :post, '/v1/vpses', {vps: {
            user: 9999,
            hostname: 'justatest',
            os_template: OsTemplate.take!.id,
            dns_resolver: DnsResolver.take!.id,
            node: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing node' do
        api :post, '/v1/vpses', {vps: {
            user: User.take!.id,
            hostname: 'justatest',
            os_template: OsTemplate.take!.id,
            dns_resolver: DnsResolver.take!.id,
            node: 9999,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing OS template' do
        api :post, '/v1/vpses', {vps: {
            user: User.take!.id,
            hostname: 'justatest',
            os_template: 9999,
            dns_resolver: DnsResolver.take!.id,
            node: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end

      it 'does not create VPS for non-existing DNS resolver' do
        api :post, '/v1/vpses', {vps: {
            user: User.take!.id,
            hostname: 'justatest',
            os_template: OsTemplate.take!.id,
            dns_resolver: 9999,
            node: Node.take!.id,
        }}

        expect(api_response).to be_failed
      end
    end
  end
end
