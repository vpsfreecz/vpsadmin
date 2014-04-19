module Commands
  class Install < Command
    description 'Add node to cluster, save public key to DB, generate configs'
    
    def options(opts, args)
      @opts = {
          :id => nil,
          :name => nil,
          :role => :node,
          :location => nil,
          :addr => nil,
          # node
          :maxvps => 30,
          :ve_private => "/vz",
          :fstype => "ext4",
          # storage
          # mailer
          # end
          :create => true,
          :propagate => false,
          :gen_configs => false,
          :ssh_key => false,
      }

      opts.on('--id ID', Integer, 'Node ID') do |id|
        @opts[:id] = id
      end

      opts.on('--name NAME', 'Node name') do |name|
        @opts[:name] = name
      end

      opts.on('--role TYPE', [:node, :storage, :mailer], 'Node type (node, storage or mailer)') do |t|
        @opts[:role] = t
      end

      opts.on('--location LOCATION', 'Node location, might be id or label') do |l|
        @opts[:location] = l
      end

      opts.on('--addr ADDR', 'Node IP address') do |addr|
        @opts[:addr] = addr
      end

      opts.on('--[no-]create', 'Update only server public key and/or generate configs, do not create node') do |i|
        @opts[:create] = i
      end

      opts.on('--[no-]propagate', 'Regenerate known_hosts on all nodes') do |p|
        @opts[:propagate] = p
      end

      opts.on('--[no-]generate-configs', 'Generate configs on this node') do |g|
        @opts[:gen_configs] = g
      end

      opts.on('--[no-]ssh-key', 'Handle SSH key and authorized_keys') do |k|
        @opts[:ssh_key] = k
      end

      opts.separator ''
      opts.separator 'Options for role NODE:'

      opts.on('--maxvps CNT', Integer, 'Max number of VPS') do |m|
        @opts[:maxvps] = m
      end

      opts.on('--ve-private PATH', 'Path to VE_PRIVATE, expands variable %{veid}') do |p|
        @opts[:ve_private] = p
      end

      opts.on('--fstype FSTYPE', [:ext4, :zfs, :zfs_compat], 'Select FS type (ext4, zfs, zfs_compat)') do |fs|
        @opts[:fstype] = fs
      end
    end

    def validate
      if @opts[:create] && (@opts[:addr].nil? || @opts[:location].nil?)
        raise OptionParser::MissingArgument.new('--addr and --location must be specified if creating new node')
      end
    end

    def prepare
      @opts
    end

    def process
      if @global_opts[:parsable]
        puts @res['node_id']
      else
        puts "#{@opts[:create] ? 'Installed' : 'Updated'} node #{@res['node_id']}"
      end
    end
  end
end
