import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    location = seed.location;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-release-retry-resolve";

    description = ''
      Exercise nodectl chain release, resolve, and retry against synthetic
      failed chains inserted directly into the database.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "transaction"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = ''
      release_chain_id = 980001
      resolve_chain_id = 980002
      retry_from_chain_id = 980003
      retry_all_chain_id = 980004
      release_port_id = 980101
      retry_from_tx_ids = [980301, 980302, 980303]
      retry_all_tx_ids = [980401, 980402]

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      def setup_recovery_fixtures(
        services,
        release_chain_id:,
        resolve_chain_id:,
        retry_from_chain_id:,
        retry_all_chain_id:,
        release_port_id:,
        retry_from_tx_ids:,
        retry_all_tx_ids:,
        node_id:,
        user_id:
      )
        services.mysql_raw(
          sql: <<~SQL
            DELETE FROM resource_locks WHERE locked_by_type = 'TransactionChain'
              AND locked_by_id IN (#{release_chain_id}, #{resolve_chain_id}, #{retry_from_chain_id}, #{retry_all_chain_id});
            DELETE FROM port_reservations WHERE id = #{release_port_id};
            DELETE FROM transaction_confirmations WHERE transaction_id IN (#{(retry_from_tx_ids + retry_all_tx_ids).join(', ')});
            DELETE FROM transactions WHERE id IN (#{(retry_from_tx_ids + retry_all_tx_ids).join(', ')});
            DELETE FROM transaction_chains WHERE id IN (#{release_chain_id}, #{resolve_chain_id}, #{retry_from_chain_id}, #{retry_all_chain_id});
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_chains
              (id, name, type, state, size, progress, user_id, urgent_rollback, concern_type)
            VALUES
              (#{release_chain_id}, 'spec_release', 'TransactionChain', 4, 0, 0, #{user_id}, 0, 0),
              (#{resolve_chain_id}, 'spec_resolve', 'TransactionChain', 5, 0, 0, #{user_id}, 0, 0),
              (#{retry_from_chain_id}, 'spec_retry_from', 'TransactionChain', 4, 3, 2, #{user_id}, 0, 0),
              (#{retry_all_chain_id}, 'spec_retry_all', 'TransactionChain', 4, 2, 2, #{user_id}, 0, 0);
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO resource_locks
              (resource, row_id, locked_by_type, locked_by_id)
            VALUES
              ('SpecTxLock', 1001, 'TransactionChain', #{release_chain_id});
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO port_reservations
              (id, node_id, addr, port, transaction_chain_id)
            VALUES
              (#{release_port_id}, #{node_id}, '192.0.2.250', 39001, #{release_chain_id});
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transactions
              (id, user_id, node_id, handle, depends_on_id, urgent, priority, status, done, input, transaction_chain_id, reversible, queue)
            VALUES
              (#{retry_from_tx_ids[0]}, #{user_id}, #{node_id}, 990301, NULL, 0, 0, 1, 1, '{}', #{retry_from_chain_id}, 0, 'general'),
              (#{retry_from_tx_ids[1]}, #{user_id}, #{node_id}, 990302, #{retry_from_tx_ids[0]}, 0, 0, 0, 1, '{}', #{retry_from_chain_id}, 0, 'general'),
              (#{retry_from_tx_ids[2]}, #{user_id}, #{node_id}, 990303, #{retry_from_tx_ids[1]}, 0, 0, 0, 1, '{}', #{retry_from_chain_id}, 0, 'general'),
              (#{retry_all_tx_ids[0]}, #{user_id}, #{node_id}, 990401, NULL, 0, 0, 1, 1, '{}', #{retry_all_chain_id}, 0, 'general'),
              (#{retry_all_tx_ids[1]}, #{user_id}, #{node_id}, 990402, #{retry_all_tx_ids[0]}, 0, 0, 0, 1, '{}', #{retry_all_chain_id}, 0, 'general');
          SQL
        )
      end

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        setup_recovery_fixtures(
          services,
          release_chain_id: release_chain_id,
          resolve_chain_id: resolve_chain_id,
          retry_from_chain_id: retry_from_chain_id,
          retry_all_chain_id: retry_all_chain_id,
          release_port_id: release_port_id,
          retry_from_tx_ids: retry_from_tx_ids,
          retry_all_tx_ids: retry_all_tx_ids,
          node_id: ${toString nodeSeed.id},
          user_id: ${toString adminUser.id}
        )
      end

      describe 'release, retry, and resolve', order: :defined do
        it 'releases chain locks and reserved ports' do
          _, output = node.succeeds("nodectl chain #{release_chain_id} release")

          expect(output).to include('RESOURCE LOCKS')
          expect(output).to include('SpecTxLock')
          expect(output).to include('Released 1 locks')
          expect(output).to include('RESERVED PORTS')
          expect(output).to include('${nodeSeed.name}.${location.domain}')
          expect(output).to include('39001')
          expect(output).to include('Released 1 ports')

          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = #{release_chain_id}"
            )
          ).to eq('0')
          expect(
            services.mysql_scalar(sql: "SELECT transaction_chain_id IS NULL FROM port_reservations WHERE id = #{release_port_id}")
          ).to eq('1')
          expect(
            services.mysql_scalar(sql: "SELECT addr IS NULL FROM port_reservations WHERE id = #{release_port_id}")
          ).to eq('1')
        end

        it 'marks failed chains as resolved' do
          node.succeeds("nodectl chain #{resolve_chain_id} resolve")

          expect(
            services.mysql_scalar(sql: "SELECT state FROM transaction_chains WHERE id = #{resolve_chain_id}")
          ).to eq('6')
        end

        it 'retries a chain from a specific transaction' do
          node.succeeds("nodectl chain #{retry_from_chain_id} retry #{retry_from_tx_ids[1]}")

          expect(
            services.mysql_rows(
              sql: "SELECT id, done, status FROM transactions WHERE transaction_chain_id = #{retry_from_chain_id} ORDER BY id"
            )
          ).to eq([
            [retry_from_tx_ids[0].to_s, '1', '1'],
            [retry_from_tx_ids[1].to_s, '0', '0'],
            [retry_from_tx_ids[2].to_s, '0', '0']
          ])
          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{retry_from_chain_id}"
            ).first
          ).to eq(['1', '1'])
        end

        it 'retries the whole chain' do
          node.succeeds("nodectl chain #{retry_all_chain_id} retry")

          expect(
            services.mysql_rows(
              sql: "SELECT id, done, status FROM transactions WHERE transaction_chain_id = #{retry_all_chain_id} ORDER BY id"
            )
          ).to eq([
            [retry_all_tx_ids[0].to_s, '0', '0'],
            [retry_all_tx_ids[1].to_s, '0', '0']
          ])
          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{retry_all_chain_id}"
            ).first
          ).to eq(['1', '0'])
        end
      end
    '';
  }
)
