# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'VpsAdmin::API::Plugins::Requests::IPQS', requires_plugins: :requests do
  subject(:client) { client_class.new('api-token') }

  let(:client_class) { VpsAdmin::API::Plugins::Requests::IPQS }

  it 'checks IP addresses with the expected URL and parses the response' do
    uri = nil
    allow(Net::HTTP).to receive(:get) do |arg|
      uri = arg
      '{"success":true,"fraud_score":12}'
    end

    response = client.check_ip('198.51.100.20', strictness: 2)

    expect(uri.to_s).to eq(
      'https://www.ipqualityscore.com/api/json/ip/api-token/198.51.100.20?strictness=2'
    )
    expect(response).to be_success
    expect(response[:fraud_score]).to eq(12)
  end

  it 'checks mail addresses with the expected URL and parses the response' do
    uri = nil
    allow(Net::HTTP).to receive(:get) do |arg|
      uri = arg
      '{"success":true,"valid":true}'
    end

    response = client.check_mail('user@example.test', strictness: 1)

    expect(uri.to_s).to eq(
      'https://www.ipqualityscore.com/api/json/email/api-token/user@example.test?strictness=1'
    )
    expect(response).to be_success
    expect(response[:valid]).to be(true)
  end

  it 'raises a useful error when IP JSON cannot be parsed' do
    allow(Net::HTTP).to receive(:get).and_return('not-json')

    expect do
      client.check_ip('198.51.100.21')
    end.to raise_error(RuntimeError, /addr="198\.51\.100\.21".*response="not-json"/)
  end

  it 'raises a useful error when mail JSON cannot be parsed' do
    allow(Net::HTTP).to receive(:get).and_return('not-json')

    expect do
      client.check_mail('user@example.test')
    end.to raise_error(RuntimeError, /mail="user@example\.test".*response="not-json"/)
  end

  it 'exposes response success and keyed values' do
    success = client_class::Response.new('{"success":true,"request_id":"ok"}')
    failure = client_class::Response.new('{"success":false,"message":"bad"}')

    expect(success).to be_success
    expect(success[:request_id]).to eq('ok')
    expect(failure).not_to be_success
    expect(failure[:message]).to eq('bad')
  end
end
