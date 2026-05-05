import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    location = seed.location;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1 = clusterSeed.node1;
    node2 = clusterSeed.node2;
  in
  {
    name = "vps-migrate";

    description = ''
      Boot a two-node vpsAdmin cluster, register pools on both nodes, create a
      VPS on node1 and migrate it to node2.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = ''
      require 'shellwords'

      location_id = ${toString location.id}
      user_id = ${toString adminUser.id}
      node1_id = ${toString node1.id}
      node2_id = ${toString node2.id}
      os_template_id = 1
      pool_label = "tank"
      pool_fs = "tank/ct"
      pool_role = "hypervisor"
      max_datasets = 100
      cpu = 1
      memory = 1024
      swap = 0
      diskspace = 10240
      ipv4 = 0
      ipv4_private = 0
      ipv6 = 0
      migration_proof_path = '/root/vpsadmin-migration-proof.txt'
      migration_proof_content = 'vps migration data retention proof'

      def self.ct_exec(machine, vps_id, command)
        machine.succeeds(
          "osctl ct exec #{Shellwords.escape(vps_id.to_s)} /bin/sh -c #{Shellwords.escape(command)}"
        )
      end

      def self.wait_for_ct_exec(machine, vps_id)
        machine.wait_until_succeeds(
          "osctl ct exec #{Shellwords.escape(vps_id.to_s)} true",
          timeout: 120
        )
      end

      def self.write_ct_file(machine, vps_id, path, value)
        ct_exec(
          machine,
          vps_id,
          "mkdir -p #{Shellwords.escape(File.dirname(path))} && " \
            "printf '%s\\n' #{Shellwords.escape(value)} > #{Shellwords.escape(path)}"
        )
      end

      def self.expect_ct_file(machine, vps_id, path, value)
        _, output = ct_exec(machine, vps_id, "cat #{Shellwords.escape(path)}")
        expect(output.strip).to eq(value)
      end

      def self.expect_ct_absent(machine, vps_id)
        wait_until_block_fails(name: "container #{vps_id} to disappear", timeout: 120) do
          machine.succeeds("osctl ct show #{Shellwords.escape(vps_id.to_s)}")
        end
      end

      before(:suite) do
        [services, node1, node2].each(&:start)
        services.wait_for_vpsadmin_api
      end

      describe 'vps migration', order: :defined do
        it 'responds to API requests' do
          services.wait_for_vpsadmin_api(timeout: 300)
        end

        it 'creates storage pool on node1' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node1_id,
              label: pool_label,
              filesystem: pool_fs,
              role: pool_role,
              is_open: true,
              max_datasets: max_datasets,
              refquota_check: true
            }
          )

          @pool1_id = output.fetch('pool').fetch('id')
        end

        it 'creates storage pool on node2' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node2_id,
              label: pool_label,
              filesystem: pool_fs,
              role: pool_role,
              is_open: true,
              max_datasets: max_datasets,
              refquota_check: true
            }
          )

          @pool2_id = output.fetch('pool').fetch('id')
        end

        it 'waits for pools to be online' do
          [@pool1_id, @pool2_id].each do |pool_id|
            wait_for_block(name: "pool #{pool_id} online") do
              _, output = services.vpsadminctl.succeeds(args: ['pool', 'show', pool_id.to_s])
              output.fetch('pool').fetch('state') == 'online'
            end
          end
        end

        it 'generates migration keys' do
          services.vpsadminctl.succeeds(
            args: %w[cluster generate_migration_keys]
          )
        end

        [node1, node2].each do |node|
          it "runs nodectl queue resume all on #{node.name}" do
            node.succeeds('nodectl queue resume all')
          end
        end

        it 'creates a VPS on node1' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[vps new],
            parameters: {
              user: user_id,
              node: node1_id,
              os_template: os_template_id,
              hostname: 'vps-test',
              cpu: cpu,
              memory: memory,
              swap: swap,
              diskspace: diskspace,
              ipv4: ipv4,
              ipv4_private: ipv4_private,
              ipv6: ipv6
            }
          )

          @vps_id = output.fetch('vps').fetch('id')
        end

        it 'starts the VPS on node1' do
          services.vpsadminctl.succeeds(args: ['vps', 'start', @vps_id.to_s])

          wait_for_block(name: 'VPS to start') do
            _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id])
            output.fetch('vps').fetch('is_running')
          end

          node1.wait_for_osctl_container(@vps_id.to_s, state: 'running', timeout: 120)
          wait_for_ct_exec(node1, @vps_id)
        end

        it 'writes data inside the VPS before migration' do
          write_ct_file(node1, @vps_id, migration_proof_path, migration_proof_content)
          expect_ct_file(node1, @vps_id, migration_proof_path, migration_proof_content)
        end

        it 'migrates the VPS to node2' do
          services.vpsadminctl.succeeds(
            args: ['vps', 'migrate', @vps_id.to_s],
            parameters: {
              node: node2_id,
              maintenance_window: false,
              send_mail: false
            }
          )

          wait_for_block(name: 'VPS to migrate and start') do
            _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id])
            vps = output.fetch('vps')
            vps.fetch('node').fetch('id') == node2_id && vps.fetch('is_running')
          end

          node2.wait_for_osctl_container(@vps_id.to_s, state: 'running', timeout: 120)
          wait_for_ct_exec(node2, @vps_id)
          expect_ct_file(node2, @vps_id, migration_proof_path, migration_proof_content)
          expect_ct_absent(node1, @vps_id)
        end
      end
    '';
  }
)
