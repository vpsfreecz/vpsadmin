# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsTsigKey::Create do
  it 'requires admins to specify the key owner' do
    with_current_context(user: SpecSeed.admin) do
      expect do
        described_class.run(name: 'admin-key', algorithm: 'hmac-sha256')
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it 'creates admin keys for the requested owner with a prefixed name' do
    with_current_context(user: SpecSeed.admin) do
      key = described_class.run(name: "admin-key-#{SecureRandom.hex(3)}", algorithm: 'hmac-sha256', user: SpecSeed.user)

      expect(key).to be_persisted
      expect(key.user).to eq(SpecSeed.user)
      expect(key.name).to start_with("#{SpecSeed.user.id}-admin-key-")
      expect(Base64.strict_decode64(key.secret).bytesize).to eq(32)
    end
  end

  it 'creates user keys for the current user with a prefixed name' do
    with_current_context(user: SpecSeed.user) do
      key = described_class.run(name: "user-key-#{SecureRandom.hex(3)}", algorithm: 'hmac-sha384')

      expect(key).to be_persisted
      expect(key.user).to eq(SpecSeed.user)
      expect(key.name).to start_with("#{SpecSeed.user.id}-user-key-")
      expect(Base64.strict_decode64(key.secret).bytesize).to eq(48)
    end
  end
end
