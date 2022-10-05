module NodeCtld
  class Commands::Dataset::RsyncDataset < Commands::Base
    handle 5229
    needs :system

    def exec
      src_path = File.join('/', @src_pool_fs, @dataset_name, 'private/')
      dst_path = File.join('/', @dst_pool_fs, @dataset_name, 'private/')
      priv_key = File.join('/', @dst_pool_name, 'conf/send-receive/key')
      ssh_cmd = "ssh -i #{priv_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=ssh-rsa -l root"

      valid_rcs = @allow_partial ? [23, 24] : [0]

      syscmd(
        "#{$CFG.get(:bin, :rsync)} -rlptgoxDHXA --numeric-ids --inplace --delete-after "+
        "-e \"#{ssh_cmd}\" "+
        "#{@src_addr}:#{src_path} #{dst_path}",
        {valid_rcs: valid_rcs}
      )
    end

    def rollback
      ok
    end
  end
end
