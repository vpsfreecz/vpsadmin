#!@ruby@/bin/ruby
require 'erb'
require 'fileutils'
require 'json'

class ConfigureContainer
  LXC_CONFIG = '@lxcConfig@'.freeze

  CTSTARTMENU = '@ctstartmenu@/bin/ctstartmenu'.freeze

  def self.run
    new.run
  end

  def run
    tpl = ERB.new(File.read(LXC_CONFIG), trim_mode: '-')
    vars = {}

    config =
      begin
        JSON.parse(File.read('/run/config/vpsadmin/config.json'))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

    vars[:hostname] = config.fetch('hostname', config.fetch('vps_id', 'vps')).to_s
    vars[:init_cmd] = config.fetch('init_cmd', '/sbin/init')
    start_menu_timeout = config.fetch('start_menu_timeout', 5)

    if start_menu_timeout > 0
      FileUtils.mkdir_p('/dev/.vpsadmin')
      FileUtils.cp(CTSTARTMENU, '/dev/.vpsadmin/ctstartmenu')
      File.chmod(0o755, '/dev/.vpsadmin/ctstartmenu')
      vars[:init_cmd] = "/dev/.vpsadmin/ctstartmenu -timeout #{start_menu_timeout} #{vars[:init_cmd]}"
    end

    result = tpl.result_with_hash(vars)

    FileUtils.mkdir_p('/var/lib/lxc/vps')
    File.write('/var/lib/lxc/vps/config', result)
  end
end

ConfigureContainer.run
