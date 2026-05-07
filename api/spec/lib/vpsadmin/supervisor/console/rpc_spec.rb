# frozen_string_literal: true

RSpec.describe VpsAdmin::Supervisor::Console::Rpc do
  describe described_class::Handler do
    subject(:handler) { described_class.new }

    let(:vps) do
      vps = Vps.new(
        user_id: SpecSeed.user.id,
        node_id: SpecSeed.node.id,
        hostname: 'console-rpc-vps',
        os_template_id: SpecSeed.os_template.id
      )

      vps.object_state =
        if Vps.respond_to?(:object_states) && Vps.object_states[:active]
          Vps.object_states[:active]
        else
          0
        end

      vps.save!(validate: false)
      vps
    end

    def create_console!(token:, expiration:)
      VpsConsole.create!(
        user: SpecSeed.user,
        vps: vps,
        token: token,
        expiration: expiration
      )
    end

    it 'returns the configured API URL' do
      SysConfig.find_by!(category: 'core', name: 'api_url').update!(
        value: 'https://api.example.test'
      )

      expect(handler.get_api_url).to eq('https://api.example.test')
    end

    it 'returns the VPS node domain for a valid console session' do
      console = create_console!(
        token: 'a' * 100,
        expiration: Time.now + 30
      )

      expect(handler.get_session_node(vps.id, console.token)).to eq(SpecSeed.node.domain_name)
    end

    it 'extends a valid console session expiration' do
      console = create_console!(
        token: 'b' * 100,
        expiration: Time.now + 30
      )
      previous_expiration = console.expiration

      handler.get_session_node(vps.id, console.token)

      expect(console.reload.expiration).to be > previous_expiration
      expect(console.expiration).to be > Time.now + 50
    end

    it 'returns nil for an expired console session' do
      console = create_console!(
        token: 'c' * 100,
        expiration: Time.now - 1
      )

      expect(handler.get_session_node(vps.id, console.token)).to be_nil
    end

    it 'returns nil for a missing console session' do
      expect(handler.get_session_node(vps.id, 'missing-token')).to be_nil
    end
  end

  describe described_class::Request do
    let(:context) { build_request_context }

    def build_request_context
      channel = instance_double(Bunny::Channel)
      exchange = instance_double(Bunny::Exchange)
      delivery_info = Struct.new(:delivery_tag).new('delivery-tag')
      properties = Struct.new(:reply_to, :correlation_id).new('reply.queue', 'corr-1')
      acks = []
      published = []

      allow(channel).to receive(:ack) { |delivery_tag| acks << delivery_tag }
      allow(exchange).to receive(:publish) do |payload, **opts|
        published << { payload: JSON.parse(payload), opts: opts }
      end

      {
        acks: acks,
        published: published,
        request: described_class.new(channel, exchange, delivery_info, properties)
      }
    end

    def request
      context.fetch(:request)
    end

    def acks
      context.fetch(:acks)
    end

    def published
      context.fetch(:published)
    end

    def last_reply
      published.fetch(-1)
    end

    it 'replies with successful handler responses' do
      handler = Class.new do
        def get_api_url
          'https://api.example.test'
        end
      end
      stub_const('VpsAdmin::Supervisor::Console::Rpc::Handler', handler)

      request.process(JSON.dump(command: 'get_api_url'))

      expect(acks).to eq(['delivery-tag'])
      expect(last_reply.fetch(:payload)).to eq(
        'status' => true,
        'response' => 'https://api.example.test'
      )
      expect(last_reply.fetch(:opts)).to include(
        persistent: true,
        content_type: 'application/json',
        routing_key: 'reply.queue',
        correlation_id: 'corr-1'
      )
    end

    it 'passes args and symbolizes kwargs' do
      handler = Class.new do
        def call(vps_id, session, renew:)
          {
            vps_id: vps_id,
            session: session,
            renew: renew
          }
        end
      end
      stub_const('VpsAdmin::Supervisor::Console::Rpc::Handler', handler)

      request.process(
        JSON.dump(
          command: 'call',
          args: [101, 'session-token'],
          kwargs: { renew: true }
        )
      )

      expect(last_reply.fetch(:payload)).to eq(
        'status' => true,
        'response' => {
          'vps_id' => 101,
          'session' => 'session-token',
          'renew' => true
        }
      )
    end

    it 'replies with an error for invalid JSON and reraises' do
      expect { request.process('{') }.to raise_error(JSON::ParserError)

      expect(acks).to eq(['delivery-tag'])
      expect(last_reply.fetch(:payload)).to eq(
        'status' => false,
        'message' => 'Unable to parse request as json'
      )
    end

    it 'replies with an error for unknown commands' do
      request.process(JSON.dump(command: 'missing_command'))

      expect(acks).to eq(['delivery-tag'])
      expect(last_reply.fetch(:payload)).to eq(
        'status' => false,
        'message' => 'Command "missing_command" not found'
      )
    end

    it 'replies with an error for handler exceptions and reraises' do
      handler = Class.new do
        def explode
          raise 'boom'
        end
      end
      stub_const('VpsAdmin::Supervisor::Console::Rpc::Handler', handler)

      expect do
        request.process(JSON.dump(command: 'explode'))
      end.to raise_error(RuntimeError, 'boom')

      expect(acks).to eq(['delivery-tag'])
      expect(last_reply.fetch(:payload)).to eq(
        'status' => false,
        'message' => 'RuntimeError: boom'
      )
    end
  end
end
