# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsTsigKey::Destroy do
  it 'destroys the TSIG key' do
    key = create_dns_tsig_key!(user: SpecSeed.user)

    expect(described_class.run(key)).to eq(key)
    expect(DnsTsigKey.exists?(key.id)).to be(false)
  end
end
