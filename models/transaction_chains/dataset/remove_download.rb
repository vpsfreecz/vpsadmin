module TransactionChains
  class Dataset::RemoveDownload < ::TransactionChain
    label 'Remove snapshot download'

    def link_chain(dl, *args)
      lock(dl)

      dl.update!(confirmed: ::SnapshotDownload.confirmed(:confirm_destroy))

      append(Transactions::Storage::RemoveDownload, args: dl) do
        edit(dl.snapshot, snapshot_download_id: nil)
        destroy(dl)
      end
    end
  end
end
