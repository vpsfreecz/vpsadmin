require 'timeout'
require 'nodectld/remote_client'
require 'nodectld/remote_control'

module NodeCtld
  # Interface for osctld daemon lifecycle hooks.
  module DaemonHook
    PRE_STOP_TIMEOUT = 'NODECTLD_PRE_STOP_TIMEOUT'.freeze
    DEFAULT_PRE_STOP_TIMEOUT = 5

    def self.pre_stop(env)
      reply = Timeout.timeout(pre_stop_timeout(env)) do
        RemoteClient.send(RemoteControl::SOCKET, :pause)
      end

      return true if reply[:status].to_s == 'ok'

      raise "nodectld rejected the pause request: #{reply[:error].inspect}"
    rescue StandardError => e
      raise "Failed to pause nodectld: #{e.class}: #{e.message}", cause: e
    end

    def self.post_resume(env)
      reply = Timeout.timeout(pre_stop_timeout(env)) do
        RemoteClient.send(RemoteControl::SOCKET, :resume)
      end

      return true if reply[:status].to_s == 'ok'

      raise "nodectld rejected the resume request: #{reply[:error].inspect}"
    rescue StandardError => e
      raise "Failed to resume nodectld: #{e.class}: #{e.message}", cause: e
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
