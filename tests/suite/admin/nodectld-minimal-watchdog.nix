import ../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    dnsSeed = import ../../../api/db/seeds/test-dns-server-node.nix;
    common = import ../network/common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = dnsSeed.dnsNode.id;
      manageCluster = false;
    };
    machines = import ../../machines/dns-server-node.nix args;

    # Accelerate only these disposable guests. Keep the production unit and
    # wrapper entry point intact so --no-wrapper or on-failure regressions fail.
    watchdogFixture =
      { lib, pkgs, ... }:
      let
        fixture = pkgs.writeText "nodectld-watchdog-fixture.rb" ''
          require 'nodectld'
          require 'nodectld/cli'

          {
            NodeCtld::TransactionWatchdog => {
              WARN_AFTER: 6, DEBUG_AFTER: 8, RESTART_AFTER: 10, WARNING_INTERVAL: 2
            },
            NodeCtld::Cli => { WATCHDOG_CHECK_INTERVAL: 1, WATCHDOG_RPC_TIMEOUT: 1 }
          }.each do |klass, constants|
            constants.each do |name, value|
              klass.send(:remove_const, name)
              klass.const_set(name, value)
            end
          end
          NodeCtld::IMPLICIT_CONFIG[:export_mounts][:update_all_interval] = 1

          module StalledTransactionPolling
            def do_commands(db)
              if File.exist?('/run/nodectld-stall-once')
                File.unlink('/run/nodectld-stall-once')
                File.write('/run/nodectld-stalled', Process.pid.to_s)
                # Model a native call that does not respond to TERM while
                # leaving status/control threads available. Keep the real
                # wrapper's 60-second TERM-to-KILL deadline.
                Signal.trap('TERM') {}
                sleep
              end
              super
            end
          end
          NodeCtld::Daemon.prepend(StalledTransactionPolling)
        '';
      in
      {
        nixpkgs.overlays = lib.mkAfter [
          (_final: prev: {
            nodectld = prev.runCommand "nodectld-watchdog-fixture" { } ''
              mkdir -p "$out/bin"
              substitute ${prev.nodectld}/bin/nodectld "$out/bin/nodectld" \
                --replace-fail 'load Gem.bin_path("nodectld", "nodectld")' \
                  'load "${fixture}"; load Gem.bin_path("nodectld", "nodectld")'
              chmod +x "$out/bin/nodectld"
            '';
          })
        ];
      };
  in
  {
    name = "admin-nodectld-minimal-watchdog";
    description = ''
      Exercise minimal-mode mail and DNS daemons without osctld, including
      watchdog recovery and systemd shutdown of a stuck transaction loop.
    '';
    tags = [
      "ci"
      "vpsadmin"
      "admin"
      "node"
      "dns"
    ];

    machines = machines // {
      services = machines.services // {
        config = {
          imports = [ machines.services.config ];
          containers.mailer.config.imports = [ watchdogFixture ];
        };
      };
      dns = machines.dns // {
        config.imports = [
          machines.dns.config
          watchdogFixture
        ];
      };
    };

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def daemon_command(machine, role, command, timeout: 180)
        command = "nixos-container run mailer -- bash -c #{command.shellescape}" if role == :mailer
        machine.succeeds(command, timeout:).last.strip
      end

      def daemon_pids(machine, role)
        parent = Integer(daemon_command(machine, role,
          'systemctl show --value --property=MainPID vpsadmin-nodectld.service'))
        expect(parent).to be > 0
        children = daemon_command(machine, role, "cat /proc/#{parent}/task/#{parent}/children").split.map(&:to_i)
        expect(children.size).to eq(1)
        [parent, children.first]
      end

      def wait_for_daemon(machine, role, previous: nil)
        pids = nil
        wait_until_block_succeeds(name: "#{role} daemon ready", timeout: 180) do
          expect(daemon_command(machine, role, 'timeout 5 nodectl status')).to include('State: running')
          pids = daemon_pids(machine, role)
          expect(pids.last).not_to eq(previous.last) if previous
          true
        end
        pids
      end

      def queue_work(services, role, label)
        services.api_ruby_json(code: <<~RUBY).fetch('chain_id')
          #{api_session_prelude(admin_user_id)}
          class TransactionChains::WatchdogTest < TransactionChain
            label 'Watchdog regression test'

            def link_chain(role, subject)
              if role == 'mailer'
                mail_custom(
                  from: 'watchdog@example.test', to: ['watchdog@example.test'],
                  subject: subject, text_plain: 'Queued watchdog regression message'
                )
              else
                server = Struct.new(:node_id).new(${toString dnsSeed.dnsNode.id})
                append(Transactions::DnsServer::Reload, args: [server])
              end
            end
          end
          chain, = TransactionChains::WatchdogTest.fire(#{role.to_s.inspect}, #{label.inspect})
          puts JSON.dump(chain_id: chain.id)
        RUBY
      end

      def expect_work_done(services, role, chain_id, label)
        expect(wait_for_vps_chain_done(services, chain_id)).to eq(services.class::CHAIN_STATES[:done])
        return unless role == :mailer

        message = services.wait_for_mailpit_message(to: 'watchdog@example.test', subject: label)
        expect(message.fetch('Text')).to include('Queued watchdog regression message')
      end

      before(:suite) do
        [services, dns].each(&:start)
        services.wait_for_vpsadmin_api
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        services.wait_for_mailpit
        dns.wait_for_service('bind.service')
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      [:mailer, :dns].each do |role|
        describe "#{role} nodectld under systemd", order: :defined do
          machine = role == :mailer ? services : dns

          it 'runs supervised without osctld across periodic updates' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, 'test ! -S /run/osctl/osctld.sock')
            properties = daemon_command(machine, role,
              'systemctl show vpsadmin-nodectld.service -p Restart -p KillMode -p TimeoutStopUSec')
            expect(properties).to include('Restart=always', 'KillMode=mixed', 'TimeoutStopUSec=1min 30s')
            label = "#{role} before watchdog recovery"
            expect_work_done(services, role, queue_work(services, role, label), label)
            daemon_command(machine, role, 'nodectl refresh')
            daemon_command(machine, role, 'nodectl update os-release')
            daemon_command(machine, role, 'nodectl update export-mounts')
            sleep 3 # Three accelerated export-mount intervals.
            expect(daemon_pids(machine, role)).to eq(original)
          end

          it 'keeps an intentional pause until the operator resumes work' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, 'nodectl pause')
            label = "#{role} after intentional pause"
            chain_id = queue_work(services, role, label)
            sleep 13 # Longer than the accelerated watchdog restart threshold.
            expect(daemon_command(machine, role, 'nodectl status')).to include('State: paused')
            expect(daemon_pids(machine, role)).to eq(original)
            expect(wait_for_chain_states_local(services, chain_id, [:queued], timeout: 5))
              .to eq(services.class::CHAIN_STATES[:queued])
            daemon_command(machine, role, 'nodectl resume')
            expect_work_done(services, role, chain_id, label)
          end

          it 'recovers stale polling even though status still responds' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, 'touch /run/nodectld-stall-once')
            wait_until_block_succeeds(name: "#{role} transaction loop stalled") do
              expect(daemon_command(machine, role, 'cat /run/nodectld-stalled')).to eq(original.last.to_s)
              true
            end
            expect(daemon_command(machine, role, 'timeout 5 nodectl status')).to include('State: running')
            label = "#{role} after stale polling"
            chain_id = queue_work(services, role, label)
            replacement = wait_for_daemon(machine, role, previous: original)
            expect(replacement.first).not_to eq(original.first)
            original.each { |pid| daemon_command(machine, role, "test ! -d /proc/#{pid}") }
            log = daemon_command(machine, role, 'journalctl -u vpsadmin-nodectld.service --no-pager -o cat')
            expect(log).to include('transaction polling is stale', 'transaction-loop backtrace:',
                                  'StalledTransactionPolling#do_commands', 'Sending SIGKILL')
            expect_work_done(services, role, chain_id, label)
          end

          it 'recovers an unresponsive child without hanging the watchdog' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, "kill -STOP #{original.last}")
            label = "#{role} after unresponsive daemon"
            chain_id = queue_work(services, role, label)
            wait_for_daemon(machine, role, previous: original)
            log = daemon_command(machine, role, 'journalctl -u vpsadmin-nodectld.service --no-pager -o cat')
            expect(log).to include('Watchdog: Failed to check daemon status:', 'Sending SIGKILL')
            expect_work_done(services, role, chain_id, label)
          end

          it 'restarts after a child crash and a nodectl restart' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, "kill -KILL #{original.last}")
            replacement = wait_for_daemon(machine, role, previous: original)
            daemon_command(machine, role, 'nodectl restart')
            restarted = wait_for_daemon(machine, role, previous: replacement)
            expect(restarted.first).to eq(replacement.first)
          end

          it 'remains supervised after nodectl stop' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, 'nodectl stop')
            replacement = wait_for_daemon(machine, role, previous: original)
            expect(replacement.first).not_to eq(original.first)
          end

          it 'stops the whole service and stays stopped until explicitly started' do
            original = wait_for_daemon(machine, role)
            daemon_command(machine, role, 'systemctl stop vpsadmin-nodectld.service', timeout: 100)
            sleep 6 # Longer than the service's RestartSec.
            expect(daemon_command(machine, role,
              'systemctl show --value --property=ActiveState vpsadmin-nodectld.service')).to eq('inactive')
            original.each { |pid| daemon_command(machine, role, "test ! -d /proc/#{pid}") }
            daemon_command(machine, role, 'systemctl start vpsadmin-nodectld.service')
            wait_for_daemon(machine, role, previous: original)
          end
        end
      end
    '';
  }
)
