# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::CloseToken do
  let(:user) { SpecSeed.user }

  it 'closes the matching token session' do
    session = create_open_session!(user:, auth_type: 'token')
    token = session.token.token

    described_class.run(user, token)

    expect(session.reload.closed_at).not_to be_nil
    expect(session.token).to be_nil
  end

  it 'raises OperationError for a missing token session' do
    expect do
      described_class.run(user, 'missing')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'session not found')
  end
end
