import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "tx-manual-confirmations";

    description = ''
      Insert a synthetic transaction chain directly into the database and verify
      nodectl chain confirmations/confirm applies each confirmation type
      correctly against a scratch SQL table.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "transaction"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = ''
      require 'yaml'

      chain_id = 970001
      tx_ids = {
        create_success: 971001,
        create_failure: 971002,
        just_create_failure: 971003,
        edit_before_rollback: 971004,
        edit_after_success: 971005,
        destroy_success: 971006,
        destroy_failure: 971007,
        just_destroy_success: 971008,
        decrement_success: 971009,
        increment_success: 971010
      }
      row_ids = {
        create_success: 970101,
        create_failure: 970102,
        just_create_failure: 970103,
        edit_before_rollback: 970104,
        edit_after_success: 970105,
        destroy_success: 970106,
        destroy_failure: 970107,
        just_destroy_success: 970108,
        decrement_success: 970109,
        increment_success: 970110
      }

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      def sql_quote(value)
        return 'NULL' if value.nil?
        return value.to_s if value.is_a?(Numeric)
        return '1' if value == true
        return '0' if value == false

        "'#{value.to_s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")}'"
      end

      def confirm_transaction(node, chain_id, tx_id, direction:, success:)
        success_flag = success ? '--success' : '--no-success'
        node.succeeds(
          "nodectl chain #{chain_id} confirm --direction #{direction} #{success_flag} #{tx_id}"
        )
      end

      def scratch_row(services, row_id)
        services.mysql_rows(
          sql: "SELECT name, flag, value, counter, confirmed FROM spec_tx_records WHERE id = #{row_id}"
        ).first
      end

      def scratch_count(services, row_id)
        services.mysql_scalar(sql: "SELECT COUNT(*) FROM spec_tx_records WHERE id = #{row_id}")
      end

      def setup_manual_confirmation_fixture(services, chain_id:, tx_ids:, row_ids:, node_id:, user_id:)
        services.mysql_raw(
          sql: <<~SQL
            DELETE FROM transaction_confirmations WHERE transaction_id IN (#{tx_ids.values.join(', ')});
            DELETE FROM transactions WHERE id IN (#{tx_ids.values.join(', ')});
            DELETE FROM transaction_chains WHERE id = #{chain_id};
            DROP TABLE IF EXISTS spec_tx_records;
            CREATE TABLE spec_tx_records (
              id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
              name VARCHAR(255) NULL,
              flag INT NULL,
              value INT NULL,
              counter INT NOT NULL DEFAULT 0,
              confirmed INT NOT NULL DEFAULT 0
            );
          SQL
        )

        record_values = [
          [row_ids[:create_success], 'create-success', nil, nil, 0, 0],
          [row_ids[:create_failure], 'create-failure', nil, nil, 0, 0],
          [row_ids[:just_create_failure], 'just-create-failure', nil, nil, 0, 0],
          [row_ids[:edit_before_rollback], 'changed', 0, 99, 10, 1],
          [row_ids[:edit_after_success], 'before', 1, 7, 0, 1],
          [row_ids[:destroy_success], 'destroy-success', nil, nil, 0, 2],
          [row_ids[:destroy_failure], 'destroy-failure', nil, nil, 0, 2],
          [row_ids[:just_destroy_success], 'just-destroy-success', nil, nil, 0, 1],
          [row_ids[:decrement_success], 'decrement-success', nil, nil, 5, 1],
          [row_ids[:increment_success], 'increment-success', nil, nil, 5, 1]
        ].map do |id, name, flag, value, counter, confirmed|
          "(#{id}, #{sql_quote(name)}, #{sql_quote(flag)}, #{sql_quote(value)}, #{counter}, #{confirmed})"
        end.join(",\n")

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO spec_tx_records (id, name, flag, value, counter, confirmed)
            VALUES
            #{record_values};
          SQL
        )

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_chains
              (id, name, type, state, size, progress, user_id, urgent_rollback, concern_type)
            VALUES
              (#{chain_id}, 'spec_manual_confirmations', 'TransactionChain', 1, #{tx_ids.size}, 0, #{user_id}, 0, 0);
          SQL
        )

        transaction_values = tx_ids.each_with_index.map do |(_name, tx_id), idx|
          "(#{tx_id}, #{user_id}, #{node_id}, #{990_100 + idx}, 0, 0, 1, 1, '{}', #{chain_id}, 0, 'general')"
        end.join(",\n")

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transactions
              (id, user_id, node_id, handle, urgent, priority, status, done, input, transaction_chain_id, reversible, queue)
            VALUES
            #{transaction_values};
          SQL
        )

        confirmation_rows = [
          [972001, tx_ids[:create_success], row_ids[:create_success], nil, 0],
          [972002, tx_ids[:create_failure], row_ids[:create_failure], nil, 0],
          [972003, tx_ids[:just_create_failure], row_ids[:just_create_failure], nil, 1],
          [
            972004,
            tx_ids[:edit_before_rollback],
            row_ids[:edit_before_rollback],
            YAML.dump({ 'name' => 'original', 'flag' => 1, 'value' => 10 }),
            2
          ],
          [
            972005,
            tx_ids[:edit_after_success],
            row_ids[:edit_after_success],
            YAML.dump({ 'name' => 'after', 'flag' => 0, 'value' => 20 }),
            3
          ],
          [972006, tx_ids[:destroy_success], row_ids[:destroy_success], nil, 4],
          [972007, tx_ids[:destroy_failure], row_ids[:destroy_failure], nil, 4],
          [972008, tx_ids[:just_destroy_success], row_ids[:just_destroy_success], nil, 5],
          [972009, tx_ids[:decrement_success], row_ids[:decrement_success], YAML.dump('counter'), 6],
          [972010, tx_ids[:increment_success], row_ids[:increment_success], YAML.dump('counter'), 7]
        ].map do |id, tx_id, row_id, attr_changes, confirm_type|
          [
            id,
            tx_id,
            sql_quote('SpecTxRecord'),
            sql_quote('spec_tx_records'),
            sql_quote(YAML.dump({ 'id' => row_id })),
            sql_quote(attr_changes),
            confirm_type,
            0
          ]
        end.map do |id, tx_id, class_name, table_name, row_pks, attr_changes, confirm_type, done|
          "(#{id}, #{tx_id}, #{class_name}, #{table_name}, #{row_pks}, #{attr_changes}, #{confirm_type}, #{done})"
        end.join(",\n")

        services.mysql_raw(
          sql: <<~SQL
            INSERT INTO transaction_confirmations
              (id, transaction_id, class_name, table_name, row_pks, attr_changes, confirm_type, done)
            VALUES
            #{confirmation_rows};
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
        setup_manual_confirmation_fixture(
          services,
          chain_id: chain_id,
          tx_ids: tx_ids,
          row_ids: row_ids,
          node_id: ${toString nodeSeed.id},
          user_id: ${toString adminUser.id}
        )
      end

      describe 'manual confirmations', order: :defined do
        it 'lists pending confirmations through nodectl' do
          _, output = node.succeeds("nodectl chain #{chain_id} confirmations")

          tx_ids.each_value do |tx_id|
            expect(output).to include("TRANSACTION ##{tx_id}")
          end

          %w[create just_create edit_before edit_after destroy just_destroy decrement increment].each do |type|
            expect(output).to include(type)
          end
        end

        it 'confirms create_type on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:create_success],
            direction: 'execute',
            success: true
          )

          expect(
            services.mysql_scalar(sql: "SELECT confirmed FROM spec_tx_records WHERE id = #{row_ids[:create_success]}")
          ).to eq('1')
        end

        it 'deletes create_type rows on rollback' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:create_failure],
            direction: 'rollback',
            success: true
          )

          expect(scratch_count(services, row_ids[:create_failure])).to eq('0')
        end

        it 'deletes just_create_type rows on rollback' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:just_create_failure],
            direction: 'rollback',
            success: true
          )

          expect(scratch_count(services, row_ids[:just_create_failure])).to eq('0')
        end

        it 'restores edit_before_type rows on rollback' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:edit_before_rollback],
            direction: 'rollback',
            success: true
          )

          expect(scratch_row(services, row_ids[:edit_before_rollback])).to eq(
            ['original', '1', '10', '10', '1']
          )
        end

        it 'applies edit_after_type rows on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:edit_after_success],
            direction: 'execute',
            success: true
          )

          expect(scratch_row(services, row_ids[:edit_after_success])).to eq(
            ['after', '0', '20', '0', '1']
          )
        end

        it 'deletes destroy_type rows on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:destroy_success],
            direction: 'execute',
            success: true
          )

          expect(scratch_count(services, row_ids[:destroy_success])).to eq('0')
        end

        it 'keeps destroy_type rows and confirms them on rollback' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:destroy_failure],
            direction: 'rollback',
            success: true
          )

          expect(scratch_count(services, row_ids[:destroy_failure])).to eq('1')
          expect(
            services.mysql_scalar(sql: "SELECT confirmed FROM spec_tx_records WHERE id = #{row_ids[:destroy_failure]}")
          ).to eq('1')
        end

        it 'deletes just_destroy_type rows on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:just_destroy_success],
            direction: 'execute',
            success: true
          )

          expect(scratch_count(services, row_ids[:just_destroy_success])).to eq('0')
        end

        it 'applies decrement_type rows on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:decrement_success],
            direction: 'execute',
            success: true
          )

          expect(
            services.mysql_scalar(sql: "SELECT counter FROM spec_tx_records WHERE id = #{row_ids[:decrement_success]}")
          ).to eq('4')
        end

        it 'applies increment_type rows on execute success' do
          confirm_transaction(
            node,
            chain_id,
            tx_ids[:increment_success],
            direction: 'execute',
            success: true
          )

          expect(
            services.mysql_scalar(sql: "SELECT counter FROM spec_tx_records WHERE id = #{row_ids[:increment_success]}")
          ).to eq('6')
        end
      end
    '';
  }
)
