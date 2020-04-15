module VpsAdmind::Utils
  module Routes
    def wait_for_route_to_clear(ip_v, addr, timeout: nil)
      timeout ||= 180
      since = Time.now

      loop do
        routes = VpsAdmind::RouteList.new(ip_v)

        unless routes.include?(addr)
          log(
            :info,
            self,
            "Waited #{Time.now - since} seconds for route #{addr} to clear"
          )
          break
        end

        if since + timeout < Time.now
          fail "The following route still exist: #{addr}"
        end

        log(:info, self, "Waiting for the following route to clear: #{addr}")
        sleep(5)
      end
    end
  end
end
