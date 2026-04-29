# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::User::CheckLogin do
  let(:user) { SpecSeed.user }
  let(:request) { build_request }

  before do
    user.reload
    user.update!(lockout: false)
  end

  it 'raises when the account is locked out' do
    user.update!(lockout: true)

    expect do
      described_class.run(user, request)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'account is locked out, contact support')
  end

  it 'executes hooks for allowed users' do
    op = described_class.new
    seen = nil

    op.connect_hook(:check_login) do |ret, user:, request:|
      seen = { user: user, request: request }
      ret
    end

    expect(op.run(user, request)).to be_nil
    expect(seen).to eq(user: user, request: request)
  end
end
