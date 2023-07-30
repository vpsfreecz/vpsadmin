require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Dataset
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Zfs
    include Utils::OsCtl

    def set
      zfs(
        :set,
        "sharenfs=\"#{@params['share_options']}\"",
        @params['name']
      ) if @params['share_options']

      zfs(
        :set,
        "quota=#{@params['quota'].to_i == 0 ? 'none' : @params['quota']}",
        @params['name']
      )
    end

    def destroy(pool_fs, name, recursive: false, trash: false)
      ds = "#{pool_fs}/#{name}"

      if trash
        unless recursive
          # Check that it has no descendants
          if zfs(:list, '-H -r -t all -o name', ds).output.strip.split("\n").length > 1
            fail "#{ds} has children, refusing to destroy"
          end
        end

        osctl(%i(trash-bin dataset add), ds)
      else
        zfs(:destroy, recursive ? '-r' : nil, ds)
      end
    end

    def snapshot(pool_fs, dataset_name)
      t = Time.now.utc
      snap = t.strftime('%Y-%m-%dT%H:%M:%S')
      zfs(:snapshot, nil, "#{pool_fs}/#{dataset_name}@#{snap}")
      [snap, t]
    end

    def rollback

    end

    def clone
      zfs(:clone, nil, "#{}")
    end
  end
end
