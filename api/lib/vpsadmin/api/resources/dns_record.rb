module VpsAdmin::API::Resources
  class DnsRecord < HaveAPI::Resource
    model ::DnsRecord
    desc 'Manage DNS records'

    params(:all) do
      integer :id, label: 'ID'
      resource DnsZone, value_label: :name
      string :type, db_name: :record_type
      string :content
      integer :ttl
      integer :priority
      bool :enabled
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS records'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        self.class.model.all
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS record'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @record = self.class.model.find(params[:dns_record_id])
      end

      def exec
        @record
      end
    end
  end
end
