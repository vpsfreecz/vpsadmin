module VpsAdmind
  class Commands::Vps::WaitForRoutes < Commands::Base
    handle 2026
    needs :log, :system, :vz

    def exec
      wait_for_routes if @direction == 'execute'
      ok
    end

    def rollback
      wait_for_routes if @direction == 'rollback'
      ok
    end

    protected
    def wait_for_routes
      timeout = @timeout || 240
      ips = syscmd("vzlist -H -o ip #{@vps_id}")[:output].strip.split

      ip_vs = {
        4 => ips.reject { |v| v.include?(':') },
        6 => ips.select { |v| v.include?(':') },
      }
      since = Time.now

      loop do
        found = []

        [4, 6].each do |ip_v|
          list = RouteList.new(ip_v)

          ip_vs[ip_v].each do |ip|
            found << ip if list.include?(ip)
          end
        end

        if found.empty?
          log(:info, self, "Waited #{Time.now - since} seconds for the routes to clear")
          break
        end

        if since + timeout < Time.now
          fail "The following routes still exist: #{found.join(', ')}"
        end

        log(:info, self, "Waiting for the following routes: #{found.join(', ')}")
        sleep(5)
      end

      ok
    end
  end
end
