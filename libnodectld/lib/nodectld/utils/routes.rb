require 'ipaddress'

module NodeCtld
  module Utils::Routes
    def wait_for_route_to_clear(ip_v, addr, prefix, timeout: nil)
      since = Time.now
      v = IPAddress.parse("#{addr}/#{prefix}")
      use_default_timeout = timeout.nil?
      effective_timeout = timeout

      loop do
        routes = RouteList.new(ip_v, 'route-check')

        unless routes.include?(v)
          log(
            :info,
            "Waited #{(Time.now - since).round(2)} seconds for route #{v.to_string} to clear"
          )
          break
        end

        if use_default_timeout
          effective_timeout = $CFG.get(:route_check, :default_timeout)
        end

        if since + effective_timeout < Time.now
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
