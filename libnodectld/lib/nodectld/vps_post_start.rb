require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsPostStart
    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::OsCtl

    class << self
      %i[run].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    # @param vps_id [Integer]
    # @param in_seconds [Integer, nil]
    def run(vps_id, in_seconds: nil)
      in_seconds ||= $CFG.get(:vps_post_start, :default_schedule_delay)

      Thread.new do
        sleep(in_seconds)
        post_run(vps_id)
      end

      nil
    end

    def log_type
      'vps-post-start'
    end

    protected

    def post_run(vps_id)
      ct = OsCtlContainer.new(osctl_parse(%i[ct show], [vps_id]))
      return if ct.state != 'running'

      VpsSshHostKeys.update_ct(ct)
      VpsOsRelease.update_ct(ct)
    end
  end
end
