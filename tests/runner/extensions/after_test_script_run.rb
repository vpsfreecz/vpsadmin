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
      elsif AfterTestScriptRunLogs.node_machine?(machine)
        AfterTestScriptRunLogs.collect_node_logs(machine)
      end
    rescue StandardError => e
      warn "after_test_script_run: log collection failed for #{machine.name}: #{e.message}"
    end
  end
end
