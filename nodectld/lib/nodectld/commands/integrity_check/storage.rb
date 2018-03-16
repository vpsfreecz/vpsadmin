module NodeCtld
  class Commands::IntegrityCheck::Storage < Commands::Base
    handle 6005
    needs :system, :zfs, :integrity

    def exec
      db = Db.new

      db.transaction do |t|
        @t = t

        @pools.each do |pool|
          check_pool(pool)
        end
      end

      db.close
      ok
    end

    def rollback
      ok
    end

    protected
    def check_pool(pool)
      @pool = pool
      exists = false
      msg = nil

      begin
        @objects = parse_pool(pool['filesystem'])
        exists = true

      rescue SystemCommandFailed => e
        msg = e.message

      ensure
        state_fact(
            @t,
            pool,
            'exists',
            true,
            exists,
            :high,
            msg
        )
      end

      return unless exists

      real_pool = find_dataset('')
      fail 'pool not found' unless pool

      pool['properties'].each do |p|
        check_property(real_pool, p)
      end

      real_special = {}

      %w(vpsadmin vpsadmin/download vpsadmin/mount).each do |v|
        tmp = find_dataset(v)

        state_fact(
            @t,
            pool,
            v,
            true,
            !tmp.nil?,
            :high,
            "dataset '#{full_ds_name(v)}' does not exist"
        )

        real_special[v] = tmp
      end

      if real_special['vpsadmin/download']
        mnt = real_special['vpsadmin/download'][:mountpoint][:value]
        downloads = Dir.glob("#{mnt}/*").map { |v| v.sub(/#{mnt}\//, '') }

        pool['downloads'].each do |dl|
          check_download(mnt, downloads, dl)
        end

        unless downloads.empty?
          puts "WTF DOWNLOADS????"
          pp downloads

          downloads.each do |dl|
            state_fact(
                @t,
                create_integrity_object(
                    @t,
                    @integrity_check_id,
                    pool,
                    'SnapshotDownload'
                ),
                'exists',
                false,
                true,
                :low,
                "download '#{dl}' exists while it shouldn't"
            )
          end
        end
      end

      pool['mount_clones'].each do |c|
        check_mount_clone(c)
      end

      pool['datasets'].each do |ds|
        check_dataset(ds)
      end

      # Remaining objects are not supposed to exist. Try to place them in
      # the tree and add false facts.
      report_stray_objects unless @objects.empty?
    end

    def check_download(mnt, list, dl)
      found = nil

      list.each_index do |i|
        if list[i] == dl['secret_key']
          found = i
          break
        end
      end

      state_fact(
          @t,
          dl,
          'dir_exists',
          true,
          !found.nil?,
          :normal,
          "download '#{dl['secret_key']}' does not exist"
      )

      file_exists = File.exists?(
          File.join(mnt, dl['secret_key'], dl['file_name'])
      )

      state_fact(
          @t,
          dl,
          'file_exists',
          true,
          (found && file_exists) ? true : false,
          :normal,
          "file '#{dl['file_name']}' does not exist"
      )

      list.delete_at(found) if found
    end

    def check_mount_clone(snap)
      clone_name = "vpsadmin/mount/#{snap['id']}.snapshot"
      real_clone = find_dataset(clone_name)

      state_fact(
          @t,
          snap,
          'exists',
          true,
          !real_clone.nil?,
          :high,
          "mount clone '#{clone_name}' of "+
          "'#{full_ds_name(snap['dataset'])}@#{snap['name']}' does not exist"
      )

      return if real_clone.nil?

      state_fact(
          @t,
          snap,
          'origin',
          "#{full_ds_name(snap['dataset'])}@#{snap['name']}",
          real_clone[:origin][:value],
          :high,
          "origin is '#{real_clone[:origin][:value]}'"
      )
    end

    def check_dataset(ds)
      real_ds = find_dataset(ds['name'])

      state_fact(
          @t,
          ds,
          'exists',
          true,
          !real_ds.nil?,
          :high,
          "dataset '#{full_ds_name(ds['name'])}' does not exist"
      )

      return if real_ds.nil?

      ds['properties'].each do |p|
        check_property(real_ds, p)
      end

      ds['snapshots'].each do |s|
        check_snapshot(ds, s)
      end

      ds['trees'].each do |t|
        check_tree(ds, t)
      end

      ds['datasets'].each do |subds|
        check_dataset(subds)
      end
    end

    def check_property(real_ds, p)
      real_p = real_ds[ p['name'].to_sym ]
      return if real_p.nil? # not all properties are supported everywhere

      state_fact(
          @t,
          p,
          'is',
          p['value'],
          real_p[:value],
          :normal,
          "#{p['name']} is #{real_p[:value]}"
      )

      state_fact(
          @t,
          p,
          'inherited',
          p['inherited'],
          real_p[:inherited],
          :normal,
          'inheritance does not match'
      )
    end

    def check_snapshot(ds, snap)
      real_snap = find_snapshot(ds['name'], snap['name'])

      state_fact(
          @t,
          snap,
          'exists',
          true,
          !real_snap.nil?,
          :high,
          "snapshot '#{full_ds_name(ds['name'])}@#{snap['name']}' does not exist"
      )

      return if real_snap.nil?

      state_fact(
          @t,
          snap,
          'reference_count',
          snap['reference_count'],
          real_snap[:clones][:value].count,
          :high,
          "reference_count of '#{full_ds_name(ds['name'])}@#{snap['name']}' "+
          "is #{real_snap[:clones][:value].count}"
      )
    end

    def check_tree(ds, tree)
      real_tree = find_dataset("#{ds['name']}/#{tree['name']}")

      state_fact(
          @t,
          tree,
          'exists',
          true,
          !real_tree.nil?,
          :high,
          "dataset tree '#{full_ds_name(ds['name'])}/#{tree['name']}' does not exist"
      )

      return if real_tree.nil?

      tree['branches'].each do |b|
        check_branch(ds, tree, b)
      end
    end

    def check_branch(ds, tree, branch)
      real_branch = find_dataset("#{ds['name']}/#{tree['name']}/#{branch['name']}")

      state_fact(
          @t,
          branch,
          'exists',
          true,
          !real_branch.nil?,
          :high,
          "dataset branch "+
          "'#{full_ds_name(ds['name'])}/#{tree['name']}/#{branch['name']}' "+
          "does not exist"
      )

      return if real_branch.nil?

      branch['snapshots'].each do |s|
        check_snapshot_in_branch(ds, tree, branch, s)
      end
    end

    def check_snapshot_in_branch(ds, tree, branch, snap)
      full_name = "#{full_ds_name(ds['name'])}/#{tree['name']}/"+
                  "#{branch['name']}@#{snap['name']}"
      real_snap = find_snapshot(
          "#{ds['name']}/#{tree['name']}/#{branch['name']}",
          snap['name']
      )

      state_fact(
          @t,
          snap,
          'exists',
          true,
          !real_snap.nil?,
          :high,
          "snapshot '#{full_ds_name(ds['name'])}/#{tree['name']}/"+
          "#{branch['name']}@#{snap['name']}' does not exist"
      )

      return if real_snap.nil?

      # FIXME: reference_count != number of clones
      # reference_count is a number of snapshots that must be deleted prior
      # this one + a possible clone for remote mount purposes.
      #state_fact(
      #    @t,
      #    snap,
      #    'reference_count',
      #    snap['reference_count'],
      #    real_snap['clones'][:value].count,
      #    :high,
      #    "reference_count of '#{full_name}' is #{real_snap['clones'][:value].count}"
      #)

      clones = real_snap[:clones][:value]

      snap['clones'].each do |c|
        check_snapshot_in_branch_clones(c, clones)
      end

      return if clones.empty?

      clones.each do |c|
        state_fact(
            @t,
            create_integrity_object(
                @t,
                @integrity_check_id,
                snap,
                'Branch'  # It is not really certain what kind of an object it is
            ),
            'exists',
            false,
            true,
            :high,
            "unexpected clone '#{c}' of '#{full_name}'"
        )
      end
    end

    def check_snapshot_in_branch_clones(snap, clones)
      full_name = "#{full_ds_name(snap['dataset'])}/#{snap['tree']}/#{snap['branch']}"

      found = nil

      clones.each_index do |i|
        if full_name == clones[i]
          found = i
          break
        end
      end

      clones.delete_at(found) if found

      state_fact(
          @t,
          snap,
          'clones',
          full_name,
          found ? full_name : nil,
          :high,
          "'#{full_name}' is not a clone"
      )
    end

    def report_stray_objects
      @objects.each do |o|
        if o[:name].start_with?('@') || o[:name].start_with?('vpsadmin/')
          parent = @pool

        else
          # Search dataset's/snapshot's closest parent in tree
          parent = find_object_parent(o)
        end

        state_fact(
            @t,
            create_integrity_object(
                @t,
                @integrity_check_id,
                parent,
                o[:type][:value] == 'filesystem' ? 'DatasetInPool' : 'SnapshotInPool'
            ),
            'exists',
            false,
            true,
            :normal,
            "object '#{o[:name]}' should not exist"
        )
      end
    end

    def find_object_parent(o)
      if o[:type][:value] == 'filesystem'
        parts = o[:name].split('/')

      else
        tmp = o[:name].split('@')
        parts = tmp[0].split('/')
      end

      parent = @pool
      search = 'datasets'

      parts.each do |name|
        tmp = nil

        if /tree\.\d+/ =~ name
          search = 'trees'

        elsif name.start_with?('branch-')
          search = 'branches'
        end

        break unless parent[search] # Dead end

        parent[search].each do |ds|
          if ds['name'].split('/').last == name
            tmp = ds
            break
          end
        end

        if tmp
          parent = tmp

        else
          break
        end
      end

      parent
    end

    def parse_pool(pool)
      objects = []
      current_obj = {}

      zfs(
          :get,
          '-r -t all -Hp -o name,property,value,source type,mounted,'+
          'mountpoint,origin,clones,quota,refquota,compression,recordsize,'+
          'sync,atime,relatime,sharenfs',
          pool
      )[:output].split("\n").each do |line|
        parts = line.split("\t")
        name = parts[0].sub!(/#{pool}/, '') || ''
        name.slice!(0) if name.start_with?('/')

        if current_obj[:name] != name
          objects << current_obj unless current_obj.empty?
          current_obj = {
              :name => name,
          }
        end

        current_obj[ parts[1].to_sym ] = {
            :value => clean_value(parts[1], parts[2]),
            :inherited => parts[3].start_with?('inherited') || parts[3] == 'default'
        }
      end

      objects << current_obj unless current_obj.empty?
      objects
    end

    def clean_value(k, v)
      return nil if %w(- none).include?(v)
      return v.to_i / 1024 / 1024 if %w(quota refquota).include?(k)
      return v.split(',') if k == 'clones'
      return v.to_i if /\A\d+\z/ =~ v
      return true if v == 'on'
      return false if v == 'off'
      v
    end

    def find_dataset(name)
      found = nil

      @objects.each_index do |i|
        if @objects[i][:name] == name
          found = i
          break
        end
      end

      found && @objects.delete_at(found)
    end

    def find_snapshot(ds, snap)
      s = "#{ds}@#{snap}"
      found = nil

      @objects.each_index do |i|
        if @objects[i][:name] == s
          found = i
          break
        end
      end

      found && @objects.delete_at(found)
    end

    def full_ds_name(ds)
      "#{@pool['filesystem']}/#{ds}"
    end
  end
end
