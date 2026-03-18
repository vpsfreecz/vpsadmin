import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-keep-going-final-state";

    description = ''
      Insert a synthetic keep-going chain into the database and verify an
      intermediate failure still allows the tail transaction to close the chain
      as done with confirmation effects based on each transaction status.
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
      UNSUPPORTED_HANDLE = 990_992

      chain_id = 982001
      tx_ids = [982101, 982102, 982103]
      failed_confirmation_id = 982201
      tail_confirmation_id = 982202
      failed_row_id = 982301
      tail_row_id = 982302

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

      def setup_keep_going_fixture(services, chain_id:, tx_ids:, failed_confirmation_id:, tail_confirmation_id:, failed_row_id:, tail_row_id:, node_id:, user_id:)
        tx1, tx2, tx3 = tx_ids

        services.mysql_raw(
          sql: <<~SQL
            DELETE FROM transaction_confirmations WHERE id IN (#{failed_confirmation_id}, #{tail_confirmation_id});
            DELETE FROM transaction_confirmations WHERE transaction_id IN (#{tx_ids.join(', ')});
            DELETE FROM transactions WHERE id IN (#{tx_ids.join(', ')});
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
          sql: <<~SQL
            INSERT INTO spec_tx_records (id, name, confirmed)
            VALUES
              (#{failed_row_id}, 'failed-create', 0),
              (#{tail_row_id}, 'before', 1);
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_chains
              (id, name, type, state, size, progress, user_id, urgent_rollback, concern_type)
            VALUES
              (#{chain_id}, 'spec_keep_going_final_state', 'TransactionChain', 1, 3, 0, #{user_id}, 0, 0);
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transactions
              (id, user_id, node_id, handle, depends_on_id, urgent, priority, status, done, input, transaction_chain_id, reversible, queue)
            VALUES
              (
                #{tx1}, #{user_id}, #{node_id}, #{NOOP_HANDLE}, NULL, 0, 0, 0, 0,
                #{sql_quote(tx_input_json(chain_id: chain_id, depends_on_id: nil, handle: NOOP_HANDLE, node_id: node_id, reversible: 0, payload: {}))},
                #{chain_id}, 0, 'general'
              ),
              (
                #{tx2}, #{user_id}, #{node_id}, #{UNSUPPORTED_HANDLE}, #{tx1}, 0, 0, 0, 0,
                '{}',
                #{chain_id}, 2, 'general'
              ),
              (
                #{tx3}, #{user_id}, #{node_id}, #{NOOP_HANDLE}, #{tx2}, 0, 0, 0, 0,
                #{sql_quote(tx_input_json(chain_id: chain_id, depends_on_id: tx2, handle: NOOP_HANDLE, node_id: node_id, reversible: 0, payload: { sleep: 4 }))},
                #{chain_id}, 0, 'general'
              );
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_confirmations
              (id, transaction_id, class_name, table_name, row_pks, attr_changes, confirm_type, done)
            VALUES
              (
                #{failed_confirmation_id}, #{tx2}, 'SpecTxRecord', 'spec_tx_records',
                #{sql_quote(YAML.dump({ 'id' => failed_row_id }))}, NULL, 0, 0
              ),
              (
                #{tail_confirmation_id}, #{tx3}, 'SpecTxRecord', 'spec_tx_records',
                #{sql_quote(YAML.dump({ 'id' => tail_row_id }))},
                #{sql_quote(YAML.dump({ 'name' => 'after' }))},
                3, 0
              );
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
        setup_keep_going_fixture(
          services,
          chain_id: chain_id,
          tx_ids: tx_ids,
          failed_confirmation_id: failed_confirmation_id,
          tail_confirmation_id: tail_confirmation_id,
          failed_row_id: failed_row_id,
          tail_row_id: tail_row_id,
          node_id: ${toString nodeSeed.id},
          user_id: ${toString adminUser.id}
        )
      end

      describe 'keep-going final state', order: :defined do
        it 'keeps the synthetic chain queued while the queue is paused' do
          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
            ).first
          ).to eq(['1', '0'])
        end

        it 'keeps going after the middle failure and closes as done' do
          node.succeeds('nodectl queue resume general')

          wait_until_block_succeeds(name: 'keep-going intermediate state') do
            expect(
              services.mysql_rows(
                sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[1]}"
              ).first
            ).to eq(['1', '0'])
            expect(
              services.mysql_rows(
                sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
              ).first
            ).to eq(['1', '2'])
            expect(
              services.mysql_rows(
                sql: "SELECT done FROM transactions WHERE id = #{tx_ids[2]}"
              ).first
            ).to eq(['0'])
            true
          end

          services.wait_for_transaction(tx_ids[1], done: 1, status: 0)
          services.wait_for_chain_state(chain_id, state: :done)
          services.wait_for_no_confirmations(chain_id)

          expect(
            services.mysql_rows(
              sql: "SELECT state, progress FROM transaction_chains WHERE id = #{chain_id}"
            ).first
          ).to eq(['2', '3'])
          expect(
            services.mysql_rows(
              sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[1]}"
            ).first
          ).to eq(['1', '0'])
          expect(
            services.mysql_rows(
              sql: "SELECT done, status FROM transactions WHERE id = #{tx_ids[2]}"
            ).first
          ).to eq(['1', '1'])
          expect(
            services.mysql_scalar(sql: "SELECT COUNT(*) FROM spec_tx_records WHERE id = #{failed_row_id}")
          ).to eq('0')
          expect(
            services.mysql_scalar(sql: "SELECT name FROM spec_tx_records WHERE id = #{tail_row_id}")
          ).to eq('after')
          expect(
            services.mysql_scalar(
              sql: <<~SQL
                SELECT COUNT(*)
                FROM transaction_confirmations c
                INNER JOIN transactions t ON t.id = c.transaction_id
                WHERE t.transaction_chain_id = #{chain_id} AND c.done = 0
              SQL
            )
          ).to eq('0')
        end
      end
    '';
  }
)
