module VpsAdmin::API::Resources
  class SnapshotDownload < HaveAPI::Resource
    model ::SnapshotDownload
    desc 'Manage download links of dataset snapshots'

    params(:input) do
      resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot',
                                                            value_label: :created_at, required: true
      resource VpsAdmin::API::Resources::Dataset::Snapshot, name: :from_snapshot,
                                                            label: 'From snapshot', value_label: :created_at
      string :format, choices: ::SnapshotDownload.formats.keys, default: 'archive',
                      fill: true
    end

    params(:filters) do
      resource Dataset, value_label: :name
      resource Dataset::Snapshot
    end

    params(:all) do
      id :id
      resource User, value_label: :login
      use :input
      string :file_name, label: 'File name'
      string :url, desc: 'URL at which the archive can be downloaded'
      integer :size, desc: 'Size of the archive in MiB'
      string :sha256sum, desc: 'Control checksum'
      bool :ready, desc: 'True if the archive is complete and ready for download',
                   db_name: :confirmed?
      datetime :expiration_date, label: 'Expiration date',
                                 desc: 'The archive is deleted when expiration date passes'
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        use :filters
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def query
        q = ::SnapshotDownload.where(with_restricted).where.not(
          confirmed: ::SnapshotDownload.confirmed(:confirm_destroy)
        )

        q = q.joins(snapshot: [:dataset]).where(datasets: { id: input[:dataset].id }) if input[:dataset]

        q = q.where(snapshot: input[:snapshot]) if input[:snapshot]

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def prepare
        @dl = ::SnapshotDownload.find_by!(with_restricted(id: path_params['snapshot_download_id']))
      end

      def exec
        @dl
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Download a snapshot'
      blocking true

      input do
        use :input
        bool :send_mail, label: 'Send notification',
                         desc: 'Notify the user when the snapshot download is ready',
                         default: true, fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict datasets: { user_id: u.id }
        allow
      end

      def exec
        snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(with_restricted(
                                                                        id: input[:snapshot].id
                                                                      ))
        from_snap = nil

        error!('this snapshot has already been made available for download') if snap.snapshot_download_id

        if input[:format] == 'incremental_stream'
          error!('from_snapshot is required') unless input[:from_snapshot]
          from_snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(
            with_restricted(id: input[:from_snapshot].id)
          )

          if from_snap.dataset_id != snap.dataset_id
            error!('from_snapshot must belong to the same dataset')
          end

        elsif input[:from_snapshot]
          error!('from_snapshot is for incremental_stream format only')
        end

        if from_snap
          if snap.history_id != from_snap.history_id
            error!('snapshot and snapshot2 must share the same history identifier')

          elsif from_snap.created_at > snap.created_at
            error!('from_snapshot must precede snapshot')
          end
        end

        opts = {
          format: input[:format].to_sym,
          from_snapshot: from_snap,
          send_mail: input[:send_mail]
        }

        dl_chain = if input[:format] == 'incremental_stream'
                     TransactionChains::Dataset::IncrementalDownload
                   else
                     TransactionChains::Dataset::FullDownload
                   end

        @chain, dl = dl_chain.fire(snap, opts)
        dl
      end

      def state_id
        @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete download link'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def exec
        dl = ::SnapshotDownload.find_by!(with_restricted(id: path_params['snapshot_download_id']))
        object_state_check!(dl.user)

        @chain, = TransactionChains::Dataset::RemoveDownload.fire(dl)
        ok!
      end

      def state_id
        @chain.id
      end
    end
  end
end
