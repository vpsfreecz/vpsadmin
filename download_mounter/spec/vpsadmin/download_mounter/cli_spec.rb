# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::DownloadMounter::Cli do
  describe '#authenticate' do
    it 'authenticates with an explicit token' do
      api = instance_double(HaveAPI::Client::Client)
      cli = described_class.new

      cli.instance_variable_set(:@api, api)
      cli.instance_variable_set(:@opts, {
                                  auth: 'token',
                                  token: 'secret-token'
                                })

      allow(api).to receive(:authenticate)

      cli.authenticate

      expect(api).to have_received(:authenticate).with(:token, token: 'secret-token')
    end
  end
end
