require 'lib/handlers/backupers/zfs/common'
require 'lib/utils/zfs'

require 'fileutils'
require 'tempfile'

module BackuperBackend
  class ExtToZfs < ZfsBackuperCommon
    def backup
      db = Db.new

      acquire_lock(db) do
        @exclude = Tempfile.new("backuper_exclude")
        @params["exclude"].each do |s|
          @exclude.puts(s)
        end
        @exclude.close

        unless File.exists?(@params["path"])
          zfs(:create, nil, @params["dataset"])
        end

        rsync([:backuper, :zfs, :rsync], {
            :exclude => @exclude.path,
            :src => mountpoint + "/",
            :dst => @params["path"],
        })
        zfs(:snapshot, nil, "#{@params["dataset"]}@backup-#{Time.new.strftime("%Y-%m-%dT%H:%M:%S")}")

        clear_backups(true) if @params["rotate_backups"]
        update_backups(db)
      end

      db.close
      ok
    end

    def restore_prepare
      target = $CFG.get(:backuper, :restore_src).gsub(/%\{veid\}/, @veid)

      syscmd("#{$CFG.get(:bin, :rm)} -rf #{target}") if File.exists?(target)

      ok
    end

    def restore_restore
      target = $CFG.get(:backuper, :restore_target) \
				.gsub(/%\{node\}/, @params["server_name"] + "." + $CFG.get(:vpsadmin, :domain)) \
				.gsub(/%\{veid\}/, @veid)

      acquire_lock(Db.new) do
        rsync([:backuper, :restore, :exttozfs, :rsync], {
            :src => "#{backup_snapshot_path}/",
            :dst => target,
        })
      end

      ok
    end

    def download
      acquire_lock(Db.new) do
        syscmd("#{$CFG.get(:bin, :mkdir)} -p #{$CFG.get(:backuper, :download)}/#{@params["secret"]}")

        if @params["server_name"]
          syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{mountdir} #{@veid}", [1,])
        else
          syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{@params["path"]}/.zfs/snapshot backup-#{@params["datetime"]}")
        end
      end

      ok
    end
  end
end
