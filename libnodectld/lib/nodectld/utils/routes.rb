require 'ipaddress'

module NodeCtld
  module Utils::Routes
    def wait_for_route_to_clear(ip_v, addr, prefix, timeout: nil)
      timeout ||= RouteCheck::TIMEOUT
      since = Time.now
      v = IPAddress.parse("#{addr}/#{prefix}")

      loop do
        routes = RouteList.new(ip_v, 'route-check')

        unless routes.include?(v)
          log(
            :info,
            "Waited #{Time.now - since} seconds for route #{v.to_string} to clear"
          )
          break
        end

        if since + timeout < Time.now
          fail "the following route exist: #{v.to_string}"
        end

        log(
          :warn,
          "Waiting for the following route to disappear: #{v.to_string}"
        )
        sleep(5)
      end
    end
  end
end
