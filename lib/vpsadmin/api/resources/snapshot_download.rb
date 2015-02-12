module VpsAdmin::API::Resources
  class SnapshotDownload < HaveAPI::Resource
    version 1
    model ::SnapshotDownload
    desc 'Manage download links of dataset snapshots'

    params(:input) do
      resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot',
               value_label: :created_at
    end

    params(:filters) do
      resource Dataset
    end

    params(:all) do
      id :id
      resource User, value_label: :login
      use :input
      bool :ready, desc: 'True if the archive is complete and ready for download',
          db_name: :confirmed?
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
          q = q..joins(snapshot: [:dataset]).where(datasets: {id: input[:dataset].id})
        end

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

        snap.download
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
