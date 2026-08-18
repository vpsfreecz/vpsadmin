require 'rack/mock'

module VpsAdmin::API
  class PasswordRecoveryWorker
    POLL_INTERVAL = 1
    ERROR_RETRY_INTERVAL = 30

    def initialize(
      poll_interval: POLL_INTERVAL,
      error_retry_interval: ERROR_RETRY_INTERVAL,
      sleep_handler: nil
    )
      @poll_interval = poll_interval
      @error_retry_interval = error_retry_interval
      @sleep_handler = sleep_handler || ->(seconds) { sleep(seconds) }
      @stopped = false
    end

    def run
      until @stopped
        result = ActiveRecord::Base.connection_pool.with_connection do
          process_next
        end
        case result
        when :idle
          @sleep_handler.call(@poll_interval)
        when :error
          @sleep_handler.call(@error_retry_interval)
        end
      end
    end

    def stop
      @stopped = true
    end

    def process_next
      return :idle unless submission_table_ready?

      submission = ::PasswordRecoverySubmission.claim_next
      return :idle unless submission

      unless ::SysConfig.get(:core, :password_recovery_enabled)
        submission.destroy!
        return :processed
      end

      Operations::Authentication::RequestPasswordRecovery.run(
        submission.identifier,
        locale: submission.locale.to_sym,
        oauth2_client: submission.oauth2_client,
        request: build_request(submission),
        submission:
      )
      submission.destroy!
      :processed
    rescue StandardError => e
      warn "[vpsAdmin API] Password recovery worker failed: #{e.class}: #{e.message}"
      submission&.retry_or_discard!
      :error
    end

    protected

    def submission_table_ready?
      @submission_table_ready ||= ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.data_source_exists?(::PasswordRecoverySubmission.table_name)
      end
    end

    def build_request(submission)
      env = Rack::MockRequest.env_for(
        '/oauth2/password-reset',
        'REMOTE_ADDR' => submission.client_ip_addr.presence || '127.0.0.1',
        'HTTP_USER_AGENT' => submission.user_agent.to_s
      )
      Sinatra::Request.new(env)
    end
  end
end
