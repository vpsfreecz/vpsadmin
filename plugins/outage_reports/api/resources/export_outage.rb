module VpsAdmin::API::Resources
  class ExportOutage < HaveAPI::Resource
    desc 'Browse exports affected by outages'
    model ::OutageExport

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      resource VpsAdmin::API::Resources::Export, value_label: :path
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::Environment
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List exports affected by outage'

      input do
        use :all, include: %i(outage export user environment location node direct)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        q = ::OutageExport.where(with_restricted)

        %i(outage export user environment location node).each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
          .limit(input[:limit])
          .offset(input[:offset])
          .order('outage_exports.id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show export affected by an outage'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @outage = ::OutageExport.find_by!(with_restricted(
          id: params[:export_outage_id],
        ))
      end

      def exec
        @outage
      end
    end
  end
end
