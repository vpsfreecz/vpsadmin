import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-invalid-signature";

    description = ''
      Unlock transaction signing, tamper with a queued transaction, and verify
      nodectld rejects the invalid signature while unsigned transactions remain
      optional in other suites.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "transaction"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix (
      args
      // {
        extraModules.services = {
          vpsadmin.api.workers = pkgs.lib.mkForce 1;
        };
      }
    );

    testScript = ''
      user_id = ${toString adminUser.id}
      node_id = ${toString nodeSeed.id}
      os_template_id = 1
      pool_label = "tank"
      pool_fs = "tank/ct"
      pool_role = "hypervisor"

      def action_state_id(output)
        output.dig('response', '_meta', 'action_state_id') || output.dig('_meta', 'action_state_id')
      end

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
      end

      describe 'invalid signature rejection', order: :defined do
        it 'creates a storage pool' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node_id,
              label: pool_label,
              filesystem: pool_fs,
              role: pool_role,
              is_open: true,
              max_datasets: 100,
              refquota_check: true
            }
          )

          @pool_id = output.fetch('pool').fetch('id')
        end

        it 'waits for the pool to become online' do
          wait_for_block(name: "pool #{@pool_id} online") do
            _, output = services.vpsadminctl.succeeds(args: ['pool', 'show', @pool_id.to_s])
            output.fetch('pool').fetch('state') == 'online'
          end
        end

        it 'creates a stopped VPS' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[vps new],
            parameters: {
              user: user_id,
              node: node_id,
              os_template: os_template_id,
              hostname: 'tx-invalid-signature-vps',
              cpu: 1,
              memory: 1024,
              swap: 0,
              diskspace: 10240,
              ipv4: 0,
              ipv4_private: 0,
              ipv6: 0,
              start: false
            }
          )

          @vps_id = output.fetch('vps').fetch('id')
        end

        it 'creates a signed chain and tampers with its payload while queued' do
          services.unlock_transaction_signing_key(passphrase: 'test')
          node.succeeds('nodectl queue pause vps')

          _, output = services.vpsadminctl.succeeds(
            args: ['vps', 'start', @vps_id.to_s],
            opts: { block: false }
          )

          @chain_id = action_state_id(output).to_i
          expect(@chain_id).to be > 0

          services.wait_for_chain_state(@chain_id, state: :queued)
          services.wait_for_chain_progress(@chain_id, progress: 0)

          @transaction_id = services.mysql_scalar(
            sql: "SELECT id FROM transactions WHERE transaction_chain_id = #{@chain_id}"
          ).to_i

          expect(@transaction_id).to be > 0
          expect(
            services.mysql_scalar(
              sql: "SELECT signature IS NOT NULL FROM transactions WHERE id = #{@transaction_id}"
            )
          ).to eq('1')

          services.mysql_raw(
            sql: "UPDATE transactions SET input = CONCAT(input, ' ') WHERE id = #{@transaction_id}"
          )
        end

        it 'fails the tampered chain and leaves the VPS stopped' do
          node.succeeds('nodectl queue resume vps')

          services.wait_for_chain_state(@chain_id, state: :failed)
          services.wait_for_no_confirmations(@chain_id)

          expect(
            services.mysql_scalar(sql: "SELECT state FROM transaction_chains WHERE id = #{@chain_id}")
          ).to eq('4')
          expect(
            services.mysql_scalar(sql: "SELECT done FROM transactions WHERE id = #{@transaction_id}")
          ).to eq('1')
          expect(
            services.mysql_scalar(sql: "SELECT status FROM transactions WHERE id = #{@transaction_id}")
          ).to eq('0')

          output = services.mysql_scalar(
            sql: "SELECT output FROM transactions WHERE id = #{@transaction_id}"
          )

          expect(output).to include('Invalid signature')
          expect(
            services.mysql_scalar(sql: "SELECT autostart_enable FROM vpses WHERE id = #{@vps_id}")
          ).to eq('0')
          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = #{@chain_id}"
            )
          ).to eq('0')

          _, vps_output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id.to_s])
          expect(vps_output.fetch('vps').fetch('is_running')).not_to be(true)
          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM vps_current_statuses WHERE vps_id = #{@vps_id} AND is_running = 1"
            )
          ).to eq('0')
        end
      end
    '';
  }
)
