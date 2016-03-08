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
      resource Dataset
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

        if input[:dataset]
          q = q.joins(snapshot: [:dataset]).where(datasets: {id: input[:dataset].id})
        end

        q = q.where(snapshot: input[:snapshot]) if input[:snapshot]

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
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
        @dl = ::SnapshotDownload.find_by!(with_restricted(id: params[:snapshot_download_id]))
      end

      def exec
        @dl
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Download a snapshot'

      input do
        use :input
        bool :send_mail, default: true, fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict datasets: {user_id: u.id}
        allow
      end

      def exec
        snap = ::Snapshot.includes(:dataset).joins(:dataset).find_by!(with_restricted(
            id: input[:snapshot].id
        ))

        if snap.snapshot_download_id
          error('this snapshot has already been made available for download')
        end

        if input[:format] == 'incremental_stream'
          error('from_snapshot is required') if !input[:from_snapshot]

        elsif input[:from_snapshot]
          error('from_snapshot is for incremental_stream format only')
        end

        if input[:from_snapshot]
          if input[:snapshot].history_id != input[:from_snapshot].history_id
            error('snapshot and snapshot2 must share the same history identifier')

          elsif input[:from_snapshot].created_at > input[:snapshot].created_at
            error('from_snapshot must precede snapshot')
          end
        end

        snap.download(
            format: input[:format].to_sym,
            from_snapshot: input[:from_snapshot],
            send_mail: input[:send_mail],
        )
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete download link'

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def exec
        dl = ::SnapshotDownload.find_by!(with_restricted(id: params[:snapshot_download_id]))
        dl.destroy
        ok
      end
    end
  end
end
