{ testFramework, ... }@testArgs:
import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
    ordinaryMachines = import ../../machines/cluster/1-node.nix args;
    # Use the same OS evaluator, packages, hardware and node module as the
    # framework. Only this disposable variant explicitly prepares compatible
    # consumer flags; the public profile refuses conflicting caller choices.
    maintenanceSystem =
      (import (args.vpsadminosPath + "/os") (
        {
          importedPkgs = pkgs;
          system = pkgs.system;
          extraArgs = {
            vpsadminos = args.vpsadminosPath;
          };
          modules = [
            (args.vpsadminosPath + "/tests/configs/vpsadminos/base.nix")
            ordinaryMachines.node.config
            ../../../nixos/profiles/storage-maintenance.nix
            ({ lib, ... }: {
              boot.zfs.pools.tank.install = lib.mkForce false;
              osctl.exportfs.enable = lib.mkForce false;
              services.prometheus.exporters.osctl.enable = lib.mkForce false;
              osctl.test-shell.shells = 1;
              system.vpsadminos.nixpkgsRevision =
                if toString pkgs.path == toString testFramework.nixpkgsPath then
                  testFramework.nixpkgsRevision
                else
                  null;
            })
          ];
        }
        // (pkgs.vpsadminosTestFrameworkInputs or { })
      )).config.system.build.toplevel;
  in
  {
    name = "admin-nodectl-refresh-and-runtime-state";

    description = ''
      Verify that nodectl refresh drives runtime publication and DB updates.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "admin"
    ];

    machines = ordinaryMachines // {
      node = ordinaryMachines.node // {
        config = {
          imports = [ ordinaryMachines.node.config ];
          system.extraDependencies = [ maintenanceSystem ];
        };
      };
    };

    testScript = common + ''
      before(:suite) do
        setup_admin_cluster(services, node)
      end

      describe 'nodectl refresh and runtime state', order: :defined do
        it 'refreshes node status and keeps read-only RPCs healthy' do
          initial_row = nil

          wait_until_block_succeeds(name: "initial node status row for node #{node1_id}") do
            initial_row = node_current_status_row(services, node_id: node1_id)
            !initial_row.nil?
          end

          initial_time = Integer(initial_row.fetch('time'))
          sleep 1

          node.succeeds('nodectl refresh', timeout: 120)

          wait_until_block_succeeds(name: "node status time advances after refresh") do
            row = node_current_status_row(services, node_id: node1_id)
            row && Integer(row.fetch('time')) > initial_time
          end

          status_response = nodectl_remote_json(node, command: :status)
          expect(status_response.fetch('status')).to eq('ok')
          expect(status_response.fetch('response').fetch('state').fetch('run')).to eq(true)

          accounting_response = nodectl_remote_json(
            node,
            command: :get,
            params: { resource: 'net_accounting' }
          )
          expect(accounting_response.fetch('status')).to eq('ok')
          expect(accounting_response.fetch('response').fetch('interfaces')).to be_a(Array)
        end

        it 'preserves Node storage through maintenance activation, boot and restoration' do
          require 'digest'
          node.wait_for_service('pool-tank')
          node.wait_for_osctl_pool('tank')
          _, ordinary_system = node.succeeds('readlink -f /run/current-system')
          _, ordinary_boot = node.succeeds('readlink -f /run/booted-system')
          _, ordinary_boot_id = node.succeeds('cat /proc/sys/kernel/random/boot_id')
          expect(ordinary_boot).to eq(ordinary_system)

          node.succeeds(<<~CMD)
            set -e
            zfs create -o mountpoint=/mnt/admin-maintenance-proof tank/admin-maintenance-proof
            printf 'retained Node payload before maintenance\\n' > /mnt/admin-maintenance-proof/payload
            sync -f /mnt/admin-maintenance-proof
          CMD
          retained_storage = lambda do
            node.succeeds(<<~CMD)[1]
              set -e
              zpool get -H -o value guid tank
              zfs get -H -o value guid tank/admin-maintenance-proof
              zfs get -H -o value org.vpsadminos.osctl:active tank
              sha256sum /mnt/admin-maintenance-proof/payload
            CMD
          end
          retained_config = lambda do
            node.succeeds(<<~CMD)[1]
              set -e
              sha256sum /etc/vpsadmin/nodectld.yml
              sha256sum /etc/vpsadmin/transaction.key
            CMD
          end
          storage_before = retained_storage.call
          config_before = retained_config.call
          expect(storage_before.lines.length).to eq(4)
          expect(storage_before.lines[0].strip).to match(/\A[0-9]+\z/)
          expect(storage_before.lines[1].strip).to match(/\A[0-9]+\z/)
          expect(storage_before.lines.last.split.first).to eq(
            Digest::SHA256.hexdigest("retained Node payload before maintenance\n")
          )

          maintenance_ready = lambda do
            node.wait_until_succeeds('test -f /run/service/pool-tank/done')
            node.succeeds(<<~CMD)
              set -e
              test ! -e /service/nodectld && test ! -L /service/nodectld || { echo 'maintenance: nodectld-service'; exit 1; }
              test ! -e /service/osctld && test ! -L /service/osctld || { echo 'maintenance: osctld-service'; exit 1; }
              links=$(find /etc/runit/runsvdir -mindepth 2 -maxdepth 2 -name nodectld -o -name osctld) || { echo 'maintenance: runlevel-query'; exit 1; }
              test -z "$links" || { echo 'maintenance: daemon-runlevels'; exit 1; }
              test ! -S /run/osctl/osctld.sock || { echo 'maintenance: osctld-socket'; exit 1; }
              test ! -e /run/osctl/shutdown || { echo 'maintenance: shutdown-marker'; exit 1; }
              test -x /etc/runit/services/nodectld/run || { echo 'maintenance: nodectld-definition'; exit 1; }
              test -x /etc/runit/services/osctld/run || { echo 'maintenance: osctld-definition'; exit 1; }
              test -x /run/current-system/sw/bin/nodectl || { echo 'maintenance: nodectl-tool'; exit 1; }
              test -x /run/current-system/sw/bin/osctl || { echo 'maintenance: osctl-tool'; exit 1; }
              test -x /run/current-system/sw/bin/osup || { echo 'maintenance: osup-tool'; exit 1; }
              test -x /run/current-system/sw/bin/svctl || { echo 'maintenance: svctl-tool'; exit 1; }
              poweroff_command=$(command -v poweroff) || { echo 'maintenance: poweroff-command'; exit 1; }
              poweroff_script=$(readlink -f "$poweroff_command") || { echo 'maintenance: poweroff-script'; exit 1; }
              selected_script=$(readlink -f ${maintenanceSystem}/sw/bin/poweroff) || { echo 'maintenance: selected-poweroff'; exit 1; }
              test "$poweroff_script" = "$selected_script" || { echo 'maintenance: poweroff-binding'; exit 1; }
            CMD
            # Separate argv avoids matching the shell's own literal service paths.
            status, = node.execute("pgrep -f '(^|/)[n]odectld([ :]|$)|/[.]nodectld-wrapped( |$)' > /dev/null")
            expect(status).to eq(1), 'maintenance: nodectld-process-absent'
            status, = node.execute("pgrep -f '(^|/)[o]sctld([ :]|$)|/[.]osctld-wrapped( |$)' > /dev/null")
            expect(status).to eq(1), 'maintenance: osctld-process-absent'
            expect(retained_storage.call).to eq(storage_before)
            expect(retained_config.call).to eq(config_before)
          end

          _, switch_output = node.succeeds('${maintenanceSystem}/bin/switch-to-configuration switch')
          expect(switch_output).to include('> sv stop nodectld', '> sv stop osctld')
          expect(switch_output).not_to include('> osctl activate')
          # Ordinary Node exit can retain its socket inode. Check only this
          # endpoint's inactivity, not descendant or physical exclusion.
          endpoint_status, endpoint_output = node.execute(<<~CMD)
            /run/current-system/sw/bin/ruby -rsocket <<'RUBY'
            parent = '/run/nodectl'
            path = '/run/nodectl/nodectld.sock'
            outcome = failure = client = nil

            begin
              raise TypeError unless File.lstat(parent).directory?

              observed = begin
                File.lstat(path)
              rescue Errno::ENOENT
                nil
              end

              if observed.nil?
                outcome = 'maintenance: nodectld-endpoint-absent'
              else
                raise TypeError unless observed.socket?

                client = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
                address = Socket.sockaddr_un(path)

                begin
                  client.connect_nonblock(address)
                  failure = 'maintenance: nodectld-endpoint-accepting'
                rescue Errno::ECONNREFUSED
                  outcome = 'maintenance: nodectld-endpoint-refused'
                rescue Errno::EISCONN
                  failure = 'maintenance: nodectld-endpoint-accepting'
                end
              end
            rescue StandardError
              failure = 'maintenance: nodectld-probe-error'
            ensure
              begin
                client.close if client
              rescue StandardError
                failure ||= 'maintenance: nodectld-probe-error'
              end
            end

            if failure || outcome.nil?
              warn(failure || 'maintenance: nodectld-probe-error')
              exit 1
            end

            puts outcome
            RUBY
          CMD
          expect(endpoint_status).to be_an(Integer), 'maintenance: nodectld-endpoint-status'
          expect(endpoint_status).to eq(0), 'maintenance: nodectld-endpoint-status'
          expect([
            "maintenance: nodectld-endpoint-absent\n",
            "maintenance: nodectld-endpoint-refused\n"
          ].include?(endpoint_output)).to eq(true), 'maintenance: nodectld-endpoint-result'
          maintenance_ready.call
          expect(node.succeeds('readlink -f /run/current-system')[1].strip).to eq('${maintenanceSystem}')
          expect(node.succeeds('readlink -f /run/booted-system')[1]).to eq(ordinary_boot)
          expect(node.succeeds('cat /proc/sys/kernel/random/boot_id')[1]).to eq(ordinary_boot_id)

          # Normal framework stop and the same Machine/disk. Last init wins;
          # this does not certify a production bootloader's persistent default.
          node.stop
          node.start(kernel_params: ['init=${maintenanceSystem}/init'], wait_for_boot: true)
          expect(node.succeeds('readlink -f /run/current-system')[1].strip).to eq('${maintenanceSystem}')
          expect(node.succeeds('readlink -f /run/booted-system')[1].strip).to eq('${maintenanceSystem}')
          _, maintenance_boot_id = node.succeeds('cat /proc/sys/kernel/random/boot_id')
          expect(maintenance_boot_id).not_to eq(ordinary_boot_id)
          node.succeeds("test ! -S /run/nodectl/nodectld.sock || { echo 'maintenance: nodectld-socket'; exit 1; }")
          maintenance_ready.call

          node.succeeds("#{Shellwords.escape(ordinary_system.strip)}/bin/switch-to-configuration switch")
          wait_for_running_nodectld(node)
          node.wait_for_service('pool-tank')
          node.wait_for_osctl_pool('tank')
          expect(node.succeeds('readlink -f /run/current-system')[1]).to eq(ordinary_system)
          expect(node.succeeds('readlink -f /run/booted-system')[1].strip).to eq('${maintenanceSystem}')
          expect(retained_storage.call).to eq(storage_before)
          expect(retained_config.call).to eq(config_before)
          status_response = nodectl_remote_json(node, command: :status)
          expect(status_response.fetch('status')).to eq('ok')
          expect(status_response.fetch('response').fetch('state').fetch('run')).to eq(true)
          accounting_response = nodectl_remote_json(node, command: :get, params: { resource: 'net_accounting' })
          expect(accounting_response.fetch('status')).to eq('ok')
          expect(accounting_response.fetch('response').fetch('interfaces')).to be_a(Array)
        end
      end
    '';
  }
) testArgs
