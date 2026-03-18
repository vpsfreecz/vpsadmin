import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-rollback-state-machine";

    description = ''
      Insert a synthetic three-step chain into the database, force a reversible
      unsupported-command failure, and verify nodectld drives the rollback state
      machine to a failed close with confirmation and cleanup side effects.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "transaction"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = ''
      require 'json'
      require 'yaml'

      NOOP_HANDLE = 10_001
      UNSUPPORTED_HANDLE = 990_991

      chain_id = 981001
      tx_ids = [981101, 981102, 981103]
      confirmation_id = 981201
      row_id = 981301
      lock_row_id = 981401
      port_id = 981501

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      def wait_for_queue_paused(node, queue_name)
        wait_until_block_succeeds(name: "#{queue_name} queue paused") do
          _, output = node.succeeds('nodectl status', timeout: 180)
          output.lines.any? { |line| line.include?(queue_name) && line.include?('paused') }
        end
      end

      def sql_quote(value)
        return 'NULL' if value.nil?
        return value.to_s if value.is_a?(Numeric)
        return '1' if value == true
        return '0' if value == false

        "'#{value.to_s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")}'"
      end

      def tx_input_json(chain_id:, depends_on_id:, handle:, node_id:, reversible:, payload: {})
        {
          transaction_chain: chain_id,
          depends_on: depends_on_id,
          handle: handle,
          node: node_id,
          reversible: reversible,
          input: payload
        }.to_json
      end

      def transaction_output(services, tx_id)
        JSON.parse(
          services.mysql_scalar(sql: "SELECT output FROM transactions WHERE id = #{tx_id}")
        )
      end

      def setup_rollback_fixture(services, chain_id:, tx_ids:, confirmation_id:, row_id:, lock_row_id:, port_id:, node_id:, user_id:)
        tx1, tx2, tx3 = tx_ids

        services.mysql_raw(
          sql: <<~SQL
            DELETE FROM transaction_confirmations WHERE id = #{confirmation_id};
            DELETE FROM transaction_confirmations WHERE transaction_id IN (#{tx_ids.join(', ')});
            DELETE FROM transactions WHERE id IN (#{tx_ids.join(', ')});
            DELETE FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = #{chain_id};
            DELETE FROM port_reservations WHERE id = #{port_id};
            DELETE FROM transaction_chains WHERE id = #{chain_id};
            DROP TABLE IF EXISTS spec_tx_records;
            CREATE TABLE spec_tx_records (
              id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
              name VARCHAR(255) NULL,
              confirmed INT NOT NULL DEFAULT 0
            );
          SQL
        )

        services.mysql_raw(
          sql: "INSERT INTO spec_tx_records (id, name, confirmed) VALUES (#{row_id}, 'rollback-create', 0)"
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_chains
              (id, name, type, state, size, progress, user_id, urgent_rollback, concern_type)
            VALUES
              (#{chain_id}, 'spec_rollback_state_machine', 'TransactionChain', 1, 3, 0, #{user_id}, 0, 0);
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transactions
              (id, user_id, node_id, handle, depends_on_id, urgent, priority, status, done, input, transaction_chain_id, reversible, queue)
            VALUES
              (
                #{tx1}, #{user_id}, #{node_id}, #{NOOP_HANDLE}, NULL, 0, 0, 0, 0,
                #{sql_quote(tx_input_json(chain_id: chain_id, depends_on_id: nil, handle: NOOP_HANDLE, node_id: node_id, reversible: 1, payload: { sleep: 4 }))},
                #{chain_id}, 1, 'general'
              ),
              (
                #{tx2}, #{user_id}, #{node_id}, #{UNSUPPORTED_HANDLE}, #{tx1}, 0, 0, 0, 0,
                '{}',
                #{chain_id}, 1, 'general'
              ),
              (
                #{tx3}, #{user_id}, #{node_id}, #{NOOP_HANDLE}, #{tx2}, 0, 0, 0, 0,
                #{sql_quote(tx_input_json(chain_id: chain_id, depends_on_id: tx2, handle: NOOP_HANDLE, node_id: node_id, reversible: 1, payload: {}))},
                #{chain_id}, 1, 'general'
              );
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_confirmations
              (id, transaction_id, class_name, table_name, row_pks, attr_changes, confirm_type, done)
            VALUES
              (
                #{confirmation_id}, #{tx1}, 'SpecTxRecord', 'spec_tx_records',
                #{sql_quote(YAML.dump({ 'id' => row_id }))}, NULL, 0, 0
              );
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO resource_locks (resource, row_id, locked_by_type, locked_by_id)
            VALUES ('SpecTxLock', #{lock_row_id}, 'TransactionChain', #{chain_id});
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO port_reservations (id, node_id, addr, port, transaction_chain_id)
            VALUES (#{port_id}, #{node_id}, '192.0.2.251', 39101, #{chain_id});
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
        node.succeeds('nodectl queue pause general')
        wait_for_queue_paused(node, 'general')
        setup_rollback_fixture(
          services,
          chain_id: chain_id,
          tx_ids: tx_ids,
          confirmation_id: confirmation_id,
          row_id: row_id,
          lock_row_id: lock_row_id,
          port_id: port_id,
          node_id: ${toString nodeSeed.id},
          user_id: ${toString adminUser.id}
        )
      end

      describe 'rollback state machine', order: :defined do
        it 'keeps the synthetic chain queued while the queue is paused' do
          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
            ).first
          ).to eq(['1', '0'])

          expect(
            services.mysql_rows(
              sql: "SELECT id, done, status FROM transactions WHERE transaction_chain_id = #{chain_id} ORDER BY id"
            )
          ).to eq([
            [tx_ids[0].to_s, '0', '0'],
            [tx_ids[1].to_s, '0', '0'],
            [tx_ids[2].to_s, '0', '0']
          ])
        end

        it 'rolls the chain back and closes it as failed' do
          node.succeeds('nodectl queue resume general')

          services.wait_for_transaction(tx_ids[1], done: 2, status: 0)

          wait_until_block_succeeds(name: 'chain enters rollbacking') do
            expect(
              services.mysql_rows(
                sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
              ).first
            ).to eq(['3', '0'])
            expect(
              services.mysql_rows(
                sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[0]}"
              ).first
            ).to eq(['1', '1'])
            expect(
              services.mysql_rows(
                sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[2]}"
              ).first
            ).to eq(['1', '0'])
            expect(
              services.mysql_rows(
                sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[1]}"
              ).first
            ).to eq(['2', '0'])
            true
          end

          services.wait_for_chain_state(chain_id, state: :failed)
          services.wait_for_no_confirmations(chain_id)

          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
            ).first
          ).to eq(['4', '0'])
          expect(
            services.mysql_rows(
              sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[0]}"
            ).first
          ).to eq(['2', '1'])
          expect(
            services.mysql_rows(
              sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[1]}"
            ).first
          ).to eq(['2', '0'])
          expect(
            services.mysql_rows(
              sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[2]}"
            ).first
          ).to eq(['1', '0'])

          expect(transaction_output(services, tx_ids[1])).to include('error' => 'Unsupported command')
          expect(transaction_output(services, tx_ids[2])).to include('error' => 'Dependency failed')
          expect(
            services.mysql_scalar(sql: "SELECT COUNT(*) FROM spec_tx_records WHERE id = #{row_id}")
          ).to eq('0')
          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM resource_locks WHERE locked_by_type = 'TransactionChain' AND locked_by_id = #{chain_id}"
            )
          ).to eq('0')
          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM port_reservations WHERE transaction_chain_id = #{chain_id}"
            )
          ).to eq('0')
          expect(
            services.mysql_scalar(
              sql: <<~SQL
                SELECT COUNT(*)
                FROM transaction_confirmations
                WHERE transaction_id = #{tx_ids[0]} AND done = 0
              SQL
            )
          ).to eq('0')
        end
      end
    '';
  }
)
