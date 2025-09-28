require 'libosctl'
require 'fileutils'
require 'json'

module NodeCtld
  class ConfigDrive
    DIR = '/run/nodectl/config-drives'.freeze

    include OsCtl::Lib::Utils::Log
    include Utils::System

    def self.create(vps_id, vps_config)
      new(vps_id, vps_config).generate
    end

    def initialize(vps_id, vps_config)
      @vps_id = vps_id
      @vps_config = vps_config
    end

    def generate
      drive_dir = $CFG.get(:vpsadmin, :config_drive_dir)
      iso = File.join(drive_dir, "#{@vps_id}.iso")
      tmpiso = "#{iso}.new"
      tmpdir = Dir.mktmpdir("vpsadmin-config-drive-#{@vps_id}-")
      vpsadmin_dir = File.join(tmpdir, 'vpsadmin')

      FileUtils.mkpath(drive_dir)

      Dir.mkdir(vpsadmin_dir)
      File.write(
        File.join(vpsadmin_dir, 'config.json'),
        @vps_config.to_distconfig.to_json
      )

      syscmd("xorriso -as mkisofs -J -R -V config-2 -o #{tmpiso} #{tmpdir}")
      File.rename(tmpiso, iso)
    ensure
      FileUtils.rm_rf(tmpdir)
    end

    def log_type
      'config-drive'
    end
  end
end
