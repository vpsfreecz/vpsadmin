module DistConfig
  module Distributions; end
  module Helpers; end
  module Network; end

  class SystemCommandFailed < StandardError
    attr_reader :cmd, :rc, :output

    def initialize(cmd, rc, output)
      @cmd = cmd
      @rc = rc
      @output = output

      super("command '#{cmd}' exited with code '#{rc}', output: '#{output}'")
    end
  end

  def self.register(distribution, klass)
    @dists ||= {}
    @dists[distribution] = klass
  end

  def self.for(distribution)
    @dists[distribution]
  end

  # @param vps_config [VpsConfig]
  # @param cmd [Symbol]
  # @param args [Array] positional arguments
  # @param kwargs [Hash] keyword arguments
  # @param opts [Hash]
  # @option opts [Boolean] :verbose
  # @option opts [String] :rootfs
  # @option opts [String] :ct
  def self.run(vps_config, cmd, args: [], kwargs: {}, opts: {})
    ErbTemplateCache.instance

    klass = self.for(vps_config.distribution.to_sym)
    d = (klass || self.for(:other)).new(vps_config, **opts)

    d.method(cmd).call(*args, **kwargs)
  end
end

require_relative 'dist_config/helpers/common'
require_relative 'dist_config/helpers/file'
require_relative 'dist_config/helpers/redhat'

require_relative 'dist_config/cloud_init'
require_relative 'dist_config/configurator'
require_relative 'dist_config/erb_template'
require_relative 'dist_config/erb_template_cache'
require_relative 'dist_config/etc_hosts'
require_relative 'dist_config/network_interface'
require_relative 'dist_config/hostname'
require_relative 'dist_config/vps_config'
require_relative 'dist_config/user_script'

require_relative 'dist_config/distributions/base'
require_relative 'dist_config/distributions/almalinux'
require_relative 'dist_config/distributions/alpine'
require_relative 'dist_config/distributions/centos'
require_relative 'dist_config/distributions/chimera'
require_relative 'dist_config/distributions/debian'
require_relative 'dist_config/distributions/devuan'
require_relative 'dist_config/distributions/fedora'
require_relative 'dist_config/distributions/gentoo'
require_relative 'dist_config/distributions/guix'
require_relative 'dist_config/distributions/nixos'
require_relative 'dist_config/distributions/opensuse'
require_relative 'dist_config/distributions/other'
require_relative 'dist_config/distributions/redhat'
require_relative 'dist_config/distributions/rocky'
require_relative 'dist_config/distributions/slackware'
require_relative 'dist_config/distributions/ubuntu'
require_relative 'dist_config/distributions/void'

require_relative 'dist_config/network/base'
require_relative 'dist_config/network/ifupdown'
require_relative 'dist_config/network/netctl'
require_relative 'dist_config/network/netifrc'
require_relative 'dist_config/network/network_manager'
require_relative 'dist_config/network/redhat_initscripts'
require_relative 'dist_config/network/redhat_network_manager'
require_relative 'dist_config/network/suse_sysconfig'
require_relative 'dist_config/network/systemd_networkd'
