module NodeCtl
  # Superclass for commands communicating with nodectld
  #
  # Commands can implement the following methods:
  #
  #  - {#options} to provide CLI options
  #  - {#validate} to validate CLI options and arguments
  #  - {#process} to process data received from nodectld
  class Command::Remote < Command::Base
    # @return [Client]
    attr_reader :client

    # Command parameters to be sent to nodectld
    # @return [Hash]
    attr_reader :params

    # Response from nodectld
    # @return [Hash]
    attr_reader :response

    def initialize
      super
      @params = {}
    end

    def execute
      @client = Client.new(global_opts[:sock])

      begin
        client.open
        client.cmd(cmd, params)
        msg = client.receive
      rescue StandardError => e
        warn "Error occured: #{e.message}"
        warn 'Are you sure that nodectld is running and configured properly?'
        return error('Cannot connect to nodectld')
      end

      if msg[:status] != 'ok'
        return error(
          msg[:error].instance_of?(Hash) ? msg[:error][:error] : msg[:error]
        )
      end

      @response = msg[:response]
      process
    end

    # Process response from nodectld
    def process; end
  end
end
