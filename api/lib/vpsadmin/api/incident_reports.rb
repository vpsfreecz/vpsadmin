module VpsAdmin::API
  module IncidentReports
    # Entry point for incoming messages
    class Handler
      # @param mailbox [::Mailbox]
      def initialize(mailbox)
        @mailbox = mailbox
      end

      # @param message [Mail::Message]
      # @param dry_run [Boolean]
      def handle_message(message, dry_run:)
        result = IncidentReports.handle_message(@mailbox, message, dry_run: dry_run)
        return false if result.nil?

        result.incidents.each do |inc|
          puts "Incident ##{inc.id} user=#{inc.user_id} vps=#{inc.vps_id} ip=#{inc.ip_address_assignment && inc.ip_address_assignment.ip_address}"
        end

        return result.processed? if dry_run

        if result.active.any?
          TransactionChains::IncidentReport::Send.fire(result, message: message)
        elsif result.incidents.any? && result.reply
          TransactionChains::IncidentReport::Reply.fire(message, result)
        end

        result.processed?
      end
    end

    # Returned by incident report block handler
    class Result
      # @return [Array<::IncidentReport>]
      attr_reader :incidents

      # @return [Array<::IncidentReport>]
      attr_reader :active

      # @return [Boolean]
      attr_reader :processed
      alias_method :processed?, :processed

      # @return [Hash]
      attr_reader :reply

      # @param incidents [Array<::IncidentReport>]
      # @param reply [Hash]
      # @option reply [String] :from
      # @option reply [Array<String>] :to
      # @param processed [Boolean, nil]
      def initialize(incidents:, reply: nil, processed: nil)
        @incidents = incidents
        @active = incidents.select do |inc|
          inc.user && inc.user.object_state == 'active' \
            && inc.vps && inc.vps.object_state == 'active'
        end
        @reply = reply
        @processed = processed.nil? ? incidents.any? : processed
      end
    end

    class Config
      def initialize(&block)
        instance_exec(&block)
      end

      # @yieldparam mailbox [Mailbox]
      # @yieldparam message [Mail::Message]
      # @yieldreturn [Result, nil]
      def handle_message(&block)
        @handle_message = block
      end

      private
      def do_handle_message(mailbox, message, dry_run:)
        @handle_message.call(mailbox, message, dry_run: dry_run)
      end
    end

    class Parser
      # @return [::Mailbox]
      attr_reader :mailbox

      # @return [Mail::Message]
      attr_reader :message

      # @return [Boolean]
      attr_reader :dry_run
      alias_method :dry_run?, :dry_run

      # @param mailbox [::Mailbox]
      # @param message [Mail::Message]
      # @param dry_run [Boolean]
      def initialize(mailbox, message, dry_run:)
        @mailbox = mailbox
        @message = message
        @dry_run = dry_run
      end

      protected
      # @param addr_str [String]
      # @param time [Time, nil]
      # @return [::IpAddressAssignment, nil]
      def find_ip_address_assignment(addr_str, time: nil)
        time ||= Time.now
        addr = IPAddress.parse(addr_str)

        # First we try a direct match which will work in most cases
        ip = ::IpAddress.find_by(ip_addr: addr.to_s, prefix: addr.prefix.to_i)

        # No direct match, the address could be from a larger network, we have to
        # search them one by one. This is rather slow and we should optimize it
        # in the future.
        if ip.nil?
          network = ::Network.where(ip_version: addr.ipv4? ? 4 : 6).detect do |net|
            net.include?(addr)
          end

          return if network.nil?

          ip = network.ip_addresses.detect { |net_ip| net_ip.include?(addr) }
        end

        # No match
        return if ip.nil?

        ip.ip_address_assignments
          .where('from_date <= ? AND (to_date >= ? OR to_date IS NULL)', time, time)
          .order('id DESC')
          .take
      end
    end

    def self.config(&block)
      @config = Config.new(&block)
    end

    def self.handle_message(mailbox, message, dry_run:)
      @config.send(:do_handle_message, mailbox, message, dry_run: dry_run)
    end
  end
end
