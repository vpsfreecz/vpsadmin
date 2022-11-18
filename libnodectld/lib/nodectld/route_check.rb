require 'json'
require 'libosctl'

module NodeCtld
  class RouteCheck
    include OsCtl::Lib::Utils::Log

    class << self
      %i(wait check check!).each do |m|
        define_method(m) do |pool_fs, ctid, *args, **kwargs|
          check = new(pool_fs, ctid)
          check.send(m, *args, **kwargs)
        end
      end
    end

    attr_reader :pool_fs, :ctid

    def initialize(pool_fs, ctid)
      @pool_fs = pool_fs
      @ctid = ctid
      @cfg = VpsConfig.open(pool_fs, ctid)
    end

    # Block until routes of selected VPS disappear from the routing table
    def wait(timeout: nil)
      since = Time.now
      use_default_timeout = timeout.nil?
      effective_timeout = timeout

      loop do
        routes = check
        break if routes.empty?

        if use_default_timeout
          effective_timeout = $CFG.get(:route_check, :default_timeout)
        end

        if since + effective_timeout < Time.now
          fail "the following routes exist: #{format_routes(routes)}"
        else
          log(
            :warn,
            "Waiting for the following routes to disappear: #{format_routes(routes)}"
          )
        end

        sleep(5)
      end

      log(:info, "Waited #{(Time.now - since).round(2)} seconds for routes to clear")
    end

    # @return [Array<VpsConfig::Route>]
    def check
      ret = []

      [4, 6].each do |ip_v|
        kernel_routes = RouteList.new(
          ip_v,
          "route-check #{pool_fs}:#{ctid} (IPv#{ip_v})"
        )

        cfg.network_interfaces.each do |netif|
          netif.routes[ip_v].each do |route|
            if kernel_routes.include?(route.address)
              ret << route
            end
          end
        end
      end

      ret
    end

    def check!
      routes = check
      return true if routes.empty?

      fail "The following routes exist: #{format_routes(routes)}"
    end

    def log_type
      "route-check #{pool_fs}:#{ctid}"
    end

    protected
    attr_reader :cfg

    def format_routes(routes)
      routes.map{ |r| r.address.to_string}.join(', ')
    end
  end
end
