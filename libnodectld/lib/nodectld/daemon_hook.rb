require 'timeout'
require 'nodectld/daemon_restart_barrier'
require 'nodectld/remote_client'
require 'nodectld/remote_control'

module NodeCtld
  # Interface for osctld daemon lifecycle hooks.
  module DaemonHook
    PRE_STOP_TIMEOUT = 'NODECTLD_PRE_STOP_TIMEOUT'.freeze
    DEFAULT_PRE_STOP_TIMEOUT = 5
    RESUME_RETRY_INTERVAL = 0.2

    def self.pre_stop(env)
      DaemonRestartBarrier.persist(reason: 'osctld-restart')
      reply = Timeout.timeout(pre_stop_timeout(env)) do
        RemoteClient.send(RemoteControl::SOCKET, :pause)
      end

      return true if reply[:status].to_s == 'ok'

      raise "nodectld rejected the pause request: #{reply[:error].inspect}"
    rescue StandardError => e
      raise "Failed to pause nodectld: #{e.class}: #{e.message}", cause: e
    end

    def self.post_resume(env)
      # A legacy upgrade resumes only after switch-to-configuration has
      # observed target osctld readiness. Keep malformed barriers paused for
      # operator recovery instead of clearing them opportunistically.
      return true if DaemonRestartBarrier.coordinator_resume?

      resume_attempted = false
      Timeout.timeout(pre_stop_timeout(env)) do
        resume_attempted = true
        send_checked(:resume)
        DaemonRestartBarrier.clear

        loop do
          return true if nodectld_unpaused_without_barrier?

          send_best_effort(:resume)
          sleep(RESUME_RETRY_INTERVAL)
        end
      end
    rescue StandardError => e
      restore_restart_barrier if resume_attempted
      raise "Failed to resume nodectld: #{e.class}: #{e.message}", cause: e
    end

    def self.nodectld_unpaused_without_barrier?
      reply = RemoteClient.send(RemoteControl::SOCKET, :status)
      return false unless reply[:status].to_s == 'ok'

      state = reply.dig(:response, :state)
      state.is_a?(Hash) \
        && state.has_key?(:pause) \
        && state[:pause] != true \
        && state[:restart_barrier] == false
    rescue StandardError
      false
    end

    def self.send_checked(command)
      reply = RemoteClient.send(RemoteControl::SOCKET, command)
      return true if reply[:status].to_s == 'ok'

      raise "nodectld rejected the #{command} request: #{reply[:error].inspect}"
    end

    def self.send_best_effort(command)
      send_checked(command)
    rescue StandardError
      false
    end

    def self.restore_restart_barrier
      errors = []
      begin
        DaemonRestartBarrier.persist(reason: 'osctld-restart')
      rescue StandardError => e
        errors << "marker: #{e.class}: #{e.message}"
      end

      errors << 'pause request failed' unless send_best_effort(:pause)
      warn "Failed to restore nodectld restart barrier: #{errors.join('; ')}" \
        unless errors.empty?
    end

    def self.pre_stop_timeout(env)
      value = env[PRE_STOP_TIMEOUT]
      return DEFAULT_PRE_STOP_TIMEOUT if value.nil? || value.empty?

      Float(value)
    rescue ArgumentError
      warn "Invalid #{PRE_STOP_TIMEOUT}=#{value.inspect}, using #{DEFAULT_PRE_STOP_TIMEOUT}s"
      DEFAULT_PRE_STOP_TIMEOUT
    end
  end
end
