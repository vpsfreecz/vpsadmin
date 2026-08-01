import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-chain-lifecycle";

    description = ''
      Pause the node vps queue, create a real VPS start action, observe the
      queued chain state, then resume the queue and verify the chain finishes
      cleanly.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "transaction"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

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

      def transaction_types(services)
        services.api_ruby_json(code: <<~RUBY)
          puts JSON.dump(
            vps_start: Transactions::Vps::Start.t_type,
            utils_no_op: Transactions::Utils::NoOp.t_type
          )
        RUBY
      end

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        @transaction_types = transaction_types(services)
      end

      describe 'transaction chain lifecycle', order: :defined do
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
              hostname: 'tx-chain-vps',
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

        it 'queues the start action while the vps queue is paused' do
          node.succeeds('nodectl queue pause vps')

          _, output = services.vpsadminctl.succeeds(
            args: ['vps', 'start', @vps_id.to_s],
            opts: { block: false }
          )

          @chain_id = action_state_id(output).to_i
          expect(@chain_id).to be > 0

          services.wait_for_chain_state(@chain_id, state: :queued)
          services.wait_for_chain_progress(@chain_id, progress: 0)

          transactions = services.mariadb_json_rows(sql: <<~SQL)
            SELECT JSON_OBJECT(
              'id', id,
              'handle', handle,
              'queue', queue,
              'done', done,
              'signature_is_null', signature IS NULL
            )
            FROM transactions
            WHERE transaction_chain_id = #{@chain_id}
            ORDER BY id
          SQL
          @transaction_id = transactions.first.fetch('id')

          expect(@transaction_id).to be > 0
          expect(
            services.mariadb_scalar(sql: "SELECT size FROM transaction_chains WHERE id = #{@chain_id}")
          ).to eq('2')
          expect(transactions.map { |row| row.fetch('handle') }).to eq(
            [
              @transaction_types.fetch('vps_start'),
              @transaction_types.fetch('utils_no_op')
            ]
          )
          expect(transactions.map { |row| row.fetch('queue') }).to eq(%w[vps general])
          expect(transactions.map { |row| row.fetch('done') }).to all(eq(0))
          expect(transactions.map { |row| row.fetch('signature_is_null') }).to all(be(true))

          _, queue_output = node.succeeds('nodectl get queue')
          expect(queue_output).to include(@chain_id.to_s)
        end

        it 'resumes the queue and completes the chain' do
          node.succeeds('nodectl queue resume vps')

          services.wait_for_chain_state(@chain_id, state: :done)
          services.wait_for_chain_progress(@chain_id, progress: 2)
          services.wait_for_no_confirmations(@chain_id)

          expect(
            services.mariadb_scalar(sql: "SELECT state FROM transaction_chains WHERE id = #{@chain_id}")
          ).to eq('2')
          expect(
            services.mariadb_scalar(sql: "SELECT done FROM transactions WHERE id = #{@transaction_id}")
          ).to eq('1')
          expect(
            services.mariadb_scalar(sql: "SELECT status FROM transactions WHERE id = #{@transaction_id}")
          ).to eq('1')
          completed_transactions = services.mariadb_json_rows(sql: <<~SQL)
            SELECT JSON_OBJECT('done', done, 'status', status)
            FROM transactions
            WHERE transaction_chain_id = #{@chain_id}
            ORDER BY id
          SQL
          expect(completed_transactions.map { |row| row.fetch('done') }).to all(eq(1))
          expect(completed_transactions.map { |row| row.fetch('status') }).to all(eq(1))
          expect(
            services.mariadb_scalar(
              sql: <<~SQL
                SELECT COUNT(*)
                FROM transaction_confirmations c
                INNER JOIN transactions t ON t.id = c.transaction_id
                WHERE t.transaction_chain_id = #{@chain_id} AND c.done = 0
              SQL
            )
          ).to eq('0')
          expect(
            services.mariadb_scalar(
              sql: "SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = #{@chain_id}"
            )
          ).to eq('0')
          expect(
            services.mariadb_scalar(
              sql: "SELECT COUNT(*) FROM port_reservations WHERE transaction_chain_id = #{@chain_id}"
            )
          ).to eq('0')

          wait_for_block(name: 'VPS to start') do
            _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id.to_s])
            output.fetch('vps').fetch('is_running')
          end
        end
      end
    '';
  }
)
