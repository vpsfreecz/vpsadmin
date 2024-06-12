module VpsAdmin::CLI::Commands
  class BackupVps < BackupDataset
    cmd :backup, :vps
    args '[VPS_ID] FILESYSTEM'
    desc 'Backup VPS locally'

    def exec(args)
      if args.size == 1 && /^\d+$/ !~ args[0]
        fs = args[0]

        ds_id = read_dataset_id(fs)

        if ds_id
          super([ds_id, fs])

        else
          ds = dataset_chooser(vps_only: true)
          super([ds.id, fs])
        end

      elsif args.size == 2
        super([@api.vps.show(args[0].to_i).dataset_id, args[1]])

      else
        super
      end
    end
  end
end
