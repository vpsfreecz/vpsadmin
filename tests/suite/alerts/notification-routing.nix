import ../../make-test.nix (
  { pkgs, ... }:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "alerts-notification-routing";

    description = ''
      Route a notification event to e-mail and webhook receivers and verify
      that the asynchronous dispatchers deliver both actions.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "alerts"
    ];

    machines = {
      services = {
        spin = "nixos";
        tags = [ "vpsadmin-services" ];
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config.imports = [ ../../configs/nixos/vpsadmin-services.nix ];
      };
    };

    testScript = common + ''
      require 'json'
      require 'openssl'

      WEBHOOK_SECRET = 'integration-secret'
      WEBHOOK_URL = 'http://127.0.0.1:18080/events'

      configure_examples do |config|
        config.default_order = :defined
      end

      def wait_for_notification_services(services)
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-notification-dispatcher-email.service')
        services.wait_for_service('vpsadmin-notification-dispatcher-webhook.service')
        services.wait_for_mailpit
      end

      def start_webhook_server(services)
        services.succeeds(<<~'SH')
          set -euo pipefail

          install -d -m 0700 /tmp/notification-webhook
          api_dir="$(systemctl show -p WorkingDirectory --value vpsadmin-api.service)"
          api_root="$(dirname "$api_dir")"

          cat > /tmp/notification-webhook/server.rb <<'RUBY'
          require 'fileutils'
          require 'json'
          require 'socket'

          dir = '/tmp/notification-webhook'
          FileUtils.mkdir_p(dir)
          server = TCPServer.new('127.0.0.1', 18080)

          Signal.trap('TERM') do
            server.close rescue nil
            exit
          end

          loop do
            socket = server.accept
            request_line = socket.gets.to_s
            headers = {}

            while (line = socket.gets)
              break if line == "\r\n" || line == "\n"

              name, value = line.split(':', 2)
              headers[name.downcase] = value.strip if name && value
            end

            content_length = headers.fetch('content-length', '0').to_i
            body = content_length.positive? ? socket.read(content_length) : ""
            request_parts = request_line.split(/\s+/, 3)
            method = request_parts[0]
            path = request_parts[1]
            payload = {
              method: method,
              path: path,
              headers: headers,
              body: body
            }

            tmp = File.join(dir, "request.#{$PROCESS_ID}.json")
            File.write(tmp, JSON.generate(payload))
            File.rename(tmp, File.join(dir, 'request.json'))

            response = 'accepted'
            socket.write(
              "HTTP/1.1 202 Accepted\r\n" \
              "Content-Type: text/plain\r\n" \
              "X-VpsAdmin-Test-Result: integration\r\n" \
              "Content-Length: #{response.bytesize}\r\n" \
              "Connection: close\r\n" \
              "\r\n" \
              "#{response}"
            )
          ensure
            socket&.close
          end
          RUBY

          "$api_root/ruby-env-wrapped/bin/ruby" /tmp/notification-webhook/server.rb \
            >/tmp/notification-webhook/server.log 2>&1 &
          echo "$!" > /tmp/notification-webhook/server.pid
        SH

        services.wait_until_succeeds(
          'curl --silent --show-error --fail-with-body --max-time 2 ' \
          '--request POST --data "{}" http://127.0.0.1:18080/events'
        )
        services.succeeds('rm -f /tmp/notification-webhook/request.json')
      end

      def stop_webhook_server(services)
        services.succeeds(<<~'SH')
          if test -s /tmp/notification-webhook/server.pid; then
            kill "$(cat /tmp/notification-webhook/server.pid)" || true
          fi
        SH
      end

      def create_notification_event(services)
        services.api_ruby_json(code: <<~RUBY)
          user = User.find(#{admin_user_id})

          EventRouteMatcher
            .joins(:event_route)
            .where(event_routes: { user_id: user.id })
            .delete_all
          NotificationReceiverAction
            .joins(:notification_receiver)
            .where(notification_receivers: { user_id: user.id })
            .delete_all
          EventRoute.where(user: user).delete_all
          NotificationReceiver.where(user: user).delete_all

          receiver = NotificationReceiver.create!(
            user: user,
            label: 'Integration notification receiver'
          )
          email_action = receiver.notification_receiver_actions.create!(
            action: :email,
            label: 'Integration e-mail',
            target_kind: :default_recipient
          )
          webhook_action = receiver.notification_receiver_actions.create!(
            action: :webhook,
            label: 'Integration webhook',
            target_kind: :custom,
            target_value: #{WEBHOOK_URL.inspect},
            secret: #{WEBHOOK_SECRET.inspect}
          )
          route = EventRoute.create!(
            user: user,
            notification_receiver: receiver,
            label: 'Integration notification route',
            event_type: 'user.test_notification',
            position: 1
          )
          route.event_route_matchers.create!(
            field: 'note',
            operator: '==',
            value: 'integration notification payload'
          )

          event = VpsAdmin::API::Events.emit!(
            'user.test_notification',
            user: user,
            subject: 'Integration notification event',
            summary: 'Integration notification summary',
            payload: { note: 'integration notification payload' }
          )
          deliveries = event.event_deliveries.order(:id).to_a

          puts JSON.dump(
            event_id: event.id,
            route_id: route.id,
            receiver_id: receiver.id,
            email_action_id: email_action.id,
            webhook_action_id: webhook_action.id,
            email_delivery_id: deliveries.find(&:email_action?)&.id,
            webhook_delivery_id: deliveries.find(&:webhook_action?)&.id,
            delivery_count: deliveries.length
          )
        RUBY
      end

      def notification_delivery_rows(services, event_id)
        services.api_ruby_json(code: <<~RUBY)
          event = Event.find(#{Integer(event_id)})
          rows = event.event_deliveries
                      .includes(:event_delivery_attempts)
                      .order(:id)
                      .map do |delivery|
            {
              id: delivery.id,
              action: delivery.action,
              state: delivery.state,
              receiver_id: delivery.notification_receiver_id,
              receiver_target_id: delivery.notification_receiver_target_id,
              target_value: delivery.target_value,
              response_status: delivery.response_status,
              response_body: delivery.response_body,
              response_headers: delivery.response_headers,
              error_summary: delivery.error_summary,
              attempt_count: delivery.attempt_count,
              attempts: delivery.event_delivery_attempts.order(:attempt_number).map do |attempt|
                {
                  action: attempt.action,
                  attempt_number: attempt.attempt_number,
                  state: attempt.state,
                  response_status: attempt.response_status,
                  response_body: attempt.response_body,
                  response_headers: attempt.response_headers,
                  error_summary: attempt.error_summary
                }
              end
            }
          end

          puts JSON.dump(rows)
        RUBY
      end

      def wait_for_notification_deliveries(services, event_id)
        rows = nil

        wait_until_block_succeeds(name: 'notification deliveries sent', timeout: 120) do
          rows = notification_delivery_rows(services, event_id)
          expect(rows.map { |row| row.fetch('action') }).to contain_exactly('email', 'webhook')

          rows_by_action = rows.to_h { |row| [row.fetch('action'), row] }
          expect(rows_by_action.fetch('email').fetch('state')).to eq('sent')
          expect(rows_by_action.fetch('email').fetch('response_status')).to eq(250)
          expect(rows_by_action.fetch('email').fetch('attempt_count')).to eq(1)
          expect(rows_by_action.fetch('email').fetch('attempts').first.fetch('state')).to eq('succeeded')

          expect(rows_by_action.fetch('webhook').fetch('state')).to eq('sent')
          expect(rows_by_action.fetch('webhook').fetch('response_status')).to eq(202)
          expect(rows_by_action.fetch('webhook').fetch('response_body')).to eq('accepted')
          expect(rows_by_action.fetch('webhook').fetch('response_headers').fetch('x-vpsadmin-test-result')).to eq(['integration'])
          expect(rows_by_action.fetch('webhook').fetch('attempt_count')).to eq(1)
          webhook_attempt = rows_by_action.fetch('webhook').fetch('attempts').first
          expect(webhook_attempt.fetch('state')).to eq('succeeded')
          expect(webhook_attempt.fetch('response_headers').fetch('x-vpsadmin-test-result')).to eq(['integration'])
          true
        end

        rows
      end

      def wait_for_webhook_request(services, event)
        request = nil

        wait_until_block_succeeds(name: 'webhook request received', timeout: 120) do
          _, output = services.succeeds('cat /tmp/notification-webhook/request.json')
          request = JSON.parse(output)
          body = JSON.parse(request.fetch('body'))
          headers = request.fetch('headers')

          expect(request.fetch('method')).to eq('POST')
          expect(request.fetch('path')).to eq('/events')
          expect(headers.fetch('content-type')).to include('application/json')
          expect(headers.fetch('x-vpsadmin-event')).to eq('user.test_notification')
          expect(headers.fetch('x-vpsadmin-delivery')).to eq(event.fetch('webhook_delivery_id').to_s)
          expect(headers.fetch('x-vpsadmin-signature-256')).to eq(
            "sha256=#{OpenSSL::HMAC.hexdigest('sha256', WEBHOOK_SECRET, request.fetch('body'))}"
          )

          expect(body.fetch('event').fetch('id')).to eq(event.fetch('event_id'))
          expect(body.fetch('event').fetch('type')).to eq('user.test_notification')
          expect(body.fetch('event').fetch('subject')).to eq('Integration notification event')
          expect(body.fetch('event').fetch('summary')).to eq('Integration notification summary')
          expect(body.fetch('event').fetch('payload').fetch('note')).to eq('integration notification payload')
          expect(body.fetch('delivery').fetch('id')).to eq(event.fetch('webhook_delivery_id'))
          expect(body.fetch('delivery').fetch('route').fetch('id')).to eq(event.fetch('route_id'))
          expect(body.fetch('delivery').fetch('receiver').fetch('id')).to eq(event.fetch('receiver_id'))
          expect(body.fetch('delivery').fetch('receiver_target').fetch('id')).to eq(event.fetch('webhook_action_id'))
          true
        end

        request
      end

      before(:suite) do
        services.start
        services.wait_for_vpsadmin_api
        wait_for_notification_services(services)
        start_webhook_server(services)
      end

      after(:suite) do
        stop_webhook_server(services)
      end

      describe 'notification routing', order: :defined do
        it 'delivers a matched event by e-mail and webhook' do
          services.clear_mailpit
          event = create_notification_event(services)
          expect(event.fetch('delivery_count')).to eq(2)
          expect(event.fetch('email_delivery_id')).not_to be_nil
          expect(event.fetch('webhook_delivery_id')).not_to be_nil

          expect_delivered_mail(
            services,
            to: ${builtins.toJSON adminUser.email},
            subject: 'Integration notification event',
            text_includes: [
              'Integration notification summary',
              'integration notification payload'
            ]
          )
          wait_for_webhook_request(services, event)
          wait_for_notification_deliveries(services, event.fetch('event_id'))
        end
      end
    '';
  }
)
