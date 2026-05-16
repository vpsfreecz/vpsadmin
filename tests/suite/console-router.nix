import ../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
  in
  {
    name = "console-router";

    description = ''
      Exercise the remote console router against a real started VPS on a
      single-node vpsAdmin cluster.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../machines/cluster/1-node.nix args;

    testScript = ''
      require 'base64'
      require 'json'
      require 'shellwords'

      configure_examples do |config|
        config.default_order = :defined
      end

      admin_user_id = ${toString adminUser.id}
      node_id = ${toString nodeSeed.id}
      primary_pool_fs = 'tank/ct'

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')

        wait_until_block_succeeds(name: "nodectld supervised on #{node.name}") do
          _, output = node.succeeds('sv check nodectld', timeout: 30)
          expect(output).to include('ok: run: nodectld')
          node.succeeds('test -S /run/nodectl/nodectld.sock', timeout: 30)
          true
        end
      end

      def wait_for_node_ready(services, node_id)
        wait_until_block_succeeds(name: "node #{node_id} ready in API") do
          _, output = services.vpsadminctl.succeeds(args: ['node', 'show', node_id.to_s])
          node = output.fetch('node')

          node.fetch('status') == true && node.fetch('pool_status') == true
        end
      end

      def wait_for_pool_online(services, pool_id)
        wait_until_block_succeeds(name: "pool #{pool_id} online") do
          _, output = services.vpsadminctl.succeeds(args: ['pool', 'show', pool_id.to_s])
          output.fetch('pool').fetch('state') == 'online'
        end
      end

      def api_session_prelude(admin_user_id)
        <<~RUBY
          user = User.find(#{admin_user_id})
          User.current = user
          UserSession.current = UserSession.create!(
            user: user,
            auth_type: 'basic',
            api_ip_addr: '127.0.0.1',
            client_version: 'console-router-integration'
          )
        RUBY
      end

      def create_pool(services, node_id:, label:, filesystem:, role:)
        _, output = services.vpsadminctl.succeeds(
          args: %w[pool create],
          parameters: {
            node: node_id,
            label: label,
            filesystem: filesystem,
            role: role,
            is_open: true,
            max_datasets: 100,
            refquota_check: true
          }
        )

        output.fetch('pool')
      end

      def create_vps(services, admin_user_id:, node_id:, hostname:)
        _, output = services.vpsadminctl.succeeds(
          args: %w[vps new],
          parameters: {
            user: admin_user_id,
            node: node_id,
            os_template: 1,
            hostname: hostname,
            cpu: 1,
            memory: 1024,
            swap: 0,
            diskspace: 10_240,
            start: true,
            ipv4: 0,
            ipv4_private: 0,
            ipv6: 0
          }
        )

        output.fetch('vps')
      end

      def wait_for_vps_on_node(services, vps_id:, node_id:, running: nil, timeout: 300)
        deadline = Time.now + timeout

        loop do
          _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
          vps = output.fetch('vps')

          node_ok = vps.fetch('node').fetch('id') == Integer(node_id)
          running_ok = running.nil? || vps.fetch('is_running') == running

          return vps if node_ok && running_ok

          raise OsVm::TimeoutError, "Timed out waiting for VPS #{vps_id}" if Time.now >= deadline

          sleep 1
        end
      end

      def wait_for_vps_exec(machine, vps_id:, timeout: 120)
        machine.wait_until_succeeds(
          "osctl ct exec #{Integer(vps_id)} true",
          timeout: timeout
        )
      end

      def vps_passwd(services, admin_user_id:, vps_id:)
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          vps = Vps.find(#{Integer(vps_id)})
          chain, password = VpsAdmin::API::Operations::Vps::Passwd.run(
            vps,
            'secure'
          )

          puts JSON.dump(chain_id: chain.id, password: password)
        RUBY
      end

      def create_console_token(services, admin_user_id:, vps_id:)
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          vps = Vps.find(#{Integer(vps_id)})
          user = User.find(#{admin_user_id})
          console = VpsConsole.find_for(vps, user) || VpsConsole.create_for!(vps, user)

          puts JSON.dump(token: console.token)
        RUBY
      end

      def curl_console_page(services, vps_id:, token:)
        url = "http://console.vpsadmin.test/console/#{vps_id}?session=#{token}"

        services.succeeds(
          "curl --silent --fail-with-body --max-time 30 #{Shellwords.escape(url)}",
          timeout: 60
        )
      end

      def curl_console_feed(services, vps_id:, token:, keys: nil)
        cmd = [
          'curl',
          '--silent',
          '--fail-with-body',
          '--max-time',
          '30',
          '--data-urlencode',
          "session=#{token}",
          '--data-urlencode',
          'width=80',
          '--data-urlencode',
          'height=25'
        ]
        cmd.concat(['--data-urlencode', "keys=#{keys}"]) unless keys.nil?
        cmd << "http://console.vpsadmin.test/console/feed/#{vps_id}"

        _, response = services.succeeds(Shellwords.join(cmd), timeout: 60)
        json = JSON.parse(response)

        expect(json.fetch('session')).to eq(true)

        Base64.decode64(json.fetch('data')).force_encoding('UTF-8').scrub
      end

      def console_output_matches?(output, from, pattern)
        slice = output[from..] || ""

        if pattern.is_a?(Regexp)
          slice.match?(pattern)
        else
          slice.include?(pattern)
        end
      end

      def wait_for_console_output(services, vps_id:, token:, output:, pattern:, name:, from: 0)
        wait_until_block_succeeds(name: name, timeout: 180) do
          output << curl_console_feed(services, vps_id: vps_id, token: token)
          console_output_matches?(output, from, pattern)
        end

        output
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'remote console router', order: :defined do
        it 'logs in through the console and runs a command' do
          pool = create_pool(
            services,
            node_id: node_id,
            label: 'console-router',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node_id,
            hostname: 'console-router'
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node_id, running: true)
          wait_for_vps_exec(node, vps_id: vps.fetch('id'))

          password_response = vps_passwd(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id')
          )
          services.wait_for_chain_state(password_response.fetch('chain_id'), state: :done)
          password = password_response.fetch('password')

          token = create_console_token(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id')
          ).fetch('token')

          _, page = curl_console_page(services, vps_id: vps.fetch('id'), token: token)
          expect(page).to include('new VpsAdminConsole')
          expect(page).to include(token)

          output = +""

          output << curl_console_feed(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            keys: "\n"
          )

          wait_for_console_output(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            output: output,
            pattern: /login:\s*/i,
            name: "console login prompt for VPS #{vps.fetch('id')}"
          )

          output << curl_console_feed(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            keys: "root\n"
          )

          wait_for_console_output(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            output: output,
            pattern: /password:\s*/i,
            name: "console password prompt for VPS #{vps.fetch('id')}"
          )

          shell_prompt_start = output.length
          output << curl_console_feed(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            keys: "#{password}\n"
          )

          wait_for_console_output(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            output: output,
            from: shell_prompt_start,
            pattern: /root@.*[#]/m,
            name: "console shell prompt for VPS #{vps.fetch('id')}"
          )

          command_output_start = output.length
          output << curl_console_feed(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            keys: "printf '%s\\n' \"$((40 + 2))\"\n"
          )

          wait_for_console_output(
            services,
            vps_id: vps.fetch('id'),
            token: token,
            output: output,
            from: command_output_start,
            pattern: /(?:^|[\r\n])42[\r\n]/,
            name: "console command output for VPS #{vps.fetch('id')}"
          )
        end
      end
    '';
  }
)
