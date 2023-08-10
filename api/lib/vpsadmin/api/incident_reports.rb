module VpsAdmin::API
  module IncidentReports
    # Entry point for incoming messages
    class Handler
      # @param mailbox [::Mailbox]
      def initialize(mailbox)
        @mailbox = mailbox
      end

      # @param message [Mail::Message]
      def handle_message(message)
        reports = IncidentReports.handle_message(@mailbox, message)

        reports.each do |report|
          puts "Incident ##{report.id} user=#{report.user_id} vps=#{report.vps_id} ip=#{report.ip_address_assignment && report.ip_address_assignment.ip_address}"
        end

        active = reports.select do |report|
          report.user && report.user.object_state == 'active' \
            && report.vps && report.vps.object_state == 'active'
        end

        TransactionChains::IncidentReport::Send.fire(active) if active.any?
        reports.any?
      end
    end

    class Config
      def initialize(&block)
        instance_exec(&block)
      end

      # @yieldparam mailbox [Mailbox]
      # @yieldparam message [Mail::Message]
      # @yieldreturn [Array<IncidentReport>]
      def handle_message(&block)
        @handle_message = block
      end

      private
      def do_handle_message(mailbox, message)
        @handle_message.call(mailbox, message)
      end
    end

    class Parser
      # @return [::Mailbox]
      attr_reader :mailbox

      # @return [Mail::Message]
      attr_reader :message

      # @param mailbox [::Mailbox]
      # @param message [Mail::Message]
      def initialize(mailbox, message)
        @mailbox = mailbox
        @message = message
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

    def self.handle_message(mailbox, message)
      @config.send(:do_handle_message, mailbox, message)
    end
  end
end
