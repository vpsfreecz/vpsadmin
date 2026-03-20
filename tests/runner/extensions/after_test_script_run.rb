# frozen_string_literal: true

require 'osvm'
require 'test-runner/hook'

module AfterTestScriptRunLogs
  LOG_LINES = 1000
  SERVICE_PREFIX = 'vpsadmin-'

  def self.services_machine?(machine)
    machine.is_a?(VpsadminServicesMachine)
  end

  def self.node_machine?(machine)
    machine.is_a?(OsVm::VpsadminosMachine)
  end

  def self.nixos_machine?(machine)
    machine.is_a?(OsVm::NixosMachine)
  end

  def self.collect_failed_service_journal(machine)
    machine.execute(<<~CMD)
      echo "[after_test_script_run] systemctl --failed"
      systemctl_output=$(systemctl --failed --no-legend --no-pager --type=service 2>&1 || true)
      printf '%s\n' "$systemctl_output"

      failed_units=$(printf '%s\n' "$systemctl_output" | awk '$1 ~ /\\.service$/ { print $1 }')

      if [ -z "$failed_units" ]; then
        echo "[after_test_script_run] no failed services found"
        exit 0
      fi

      for unit in $failed_units; do
        echo "[after_test_script_run] journalctl --no-pager -n #{LOG_LINES} -u ${unit}"
        journalctl --no-pager -n #{LOG_LINES} -u "${unit}"
        echo
      done
    CMD
  end

  def self.collect_service_journal(machine)
    machine.execute(<<~CMD)
      units=$(systemctl list-units --type=service '#{SERVICE_PREFIX}*' --all --no-legend --no-pager | awk '{print $1}')

      if [ -z "$units" ]; then
        echo "[after_test_script_run] no #{SERVICE_PREFIX} services found"
        exit 0
      fi

      for unit in $units; do
        echo "[after_test_script_run] journalctl --no-pager -n #{LOG_LINES} -u ${unit}"
        journalctl --no-pager -n #{LOG_LINES} -u "${unit}"
        echo
      done
    CMD
  end

  def self.collect_transaction_debug(machine)
    machine.execute(<<~CMD)
      mysql_query() {
        echo "[after_test_script_run] mysql: $1"
        mysql --batch --raw --table \
          --user=api \
          --password="$(cat /etc/vpsadmin-test/mariadb-api-password)" \
          vpsadmin \
          -e "$1"
        echo
      }

      mysql_query "SELECT id, type, state, size, progress, urgent_rollback, created_at FROM transaction_chains ORDER BY id DESC LIMIT 25"
      mysql_query "SELECT id, transaction_chain_id, node_id, vps_id, handle, depends_on_id, urgent, priority, status, done, reversible, queue, signature IS NOT NULL AS has_signature, started_at, finished_at FROM transactions ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT id, transaction_id, class_name, table_name, confirm_type, done FROM transaction_confirmations ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT resource, row_id, locked_by_type, locked_by_id, created_at FROM resource_locks ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT node_id, addr, port, transaction_chain_id FROM port_reservations WHERE transaction_chain_id IS NOT NULL ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT id, dataset_id, pool_id, label, min_snapshots, max_snapshots, snapshot_max_age, confirmed FROM dataset_in_pools ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT id, dataset_id, name, history_id, confirmed, created_at FROM snapshots ORDER BY id DESC LIMIT 200"
      mysql_query "SELECT id, dataset_in_pool_id, snapshot_id, reference_count, confirmed FROM snapshot_in_pools ORDER BY id DESC LIMIT 200"
      mysql_query "SELECT id, dataset_in_pool_id, head, confirmed FROM dataset_trees ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT id, dataset_tree_id, name, head, confirmed FROM branches ORDER BY id DESC LIMIT 100"
      mysql_query "SELECT id, snapshot_in_pool_id, snapshot_in_pool_in_branch_id, branch_id, confirmed FROM snapshot_in_pool_in_branches ORDER BY id DESC LIMIT 200"
      mysql_query "SELECT id, snapshot_in_pool_id, user_namespace_map_id, name, state, confirmed FROM snapshot_in_pool_clones ORDER BY id DESC LIMIT 100"
    CMD
  end

  def self.collect_node_logs(machine)
    %w[/var/log/nodectld /var/log/osctld].each do |log|
      machine.execute(<<~CMD)
        if [ -f #{log} ]; then
          echo "[after_test_script_run] tail -n #{LOG_LINES} #{log}"
          tail -n #{LOG_LINES} #{log}
        else
          echo "[after_test_script_run] #{log} missing"
        fi
      CMD
    end

    machine.execute(<<~CMD)
      echo "[after_test_script_run] zfs list -r -t filesystem,snapshot tank"
      zfs list -r -t filesystem,snapshot tank || true
    CMD

    machine.execute(<<~CMD)
      echo "[after_test_script_run] zfs get -r -H -o name,property,value origin,clones tank"
      zfs get -r -H -o name,property,value origin,clones tank || true
    CMD
  end
end

TestRunner::Hook.subscribe(:after_test_script_run) do |script_result:, machines:, **|
  next if script_result.expected_result?

  machines.each_value do |machine|
    next unless machine.can_execute?

    begin
      if AfterTestScriptRunLogs.nixos_machine?(machine)
        AfterTestScriptRunLogs.collect_failed_service_journal(machine)
      end

      if AfterTestScriptRunLogs.services_machine?(machine)
        AfterTestScriptRunLogs.collect_service_journal(machine)
        AfterTestScriptRunLogs.collect_transaction_debug(machine)
      elsif AfterTestScriptRunLogs.node_machine?(machine)
        AfterTestScriptRunLogs.collect_node_logs(machine)
      end
    rescue StandardError => e
      warn "after_test_script_run: log collection failed for #{machine.name}: #{e.message}"
    end
  end
end
