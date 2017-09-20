module TransactionChains
  class Dataset::RemoveDownload < ::TransactionChain
    label 'Remove'

    def link_chain(dl, *args)
      lock(dl)
      concerns(:affect, [dl.class.name, dl.id])

      dl.update!(confirmed: ::SnapshotDownload.confirmed(:confirm_destroy))

      append(Transactions::Storage::RemoveDownload, args: dl) do
        edit(dl.snapshot, snapshot_download_id: nil) if dl.snapshot
        destroy(dl)
      end
    end
  end
end
