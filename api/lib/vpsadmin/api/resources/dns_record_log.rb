module VpsAdmin::API::Resources
  class DnsRecordLog < HaveAPI::Resource
    model ::DnsRecordLog
    desc 'Browse DNS record logs'

    params(:all) do
      integer :id, label: 'ID'
      resource User, value_label: :login
      integer :raw_user_id
      resource DnsZone, value_label: :name, label: 'DNS zone'
      string :dns_zone_name, label: 'DNS zone name'
      string :change_type, label: 'Change type', choices: ::DnsRecordLog.change_types.keys.map(&:to_s)
      string :name
      string :type, db_name: :record_type, choices: %w[A AAAA CNAME MX NS PTR SRV TXT]
      custom :attr_changes, label: 'Attribute changes'
      resource TransactionChain, value_label: :name
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS record logs'

      input do
        resource User, value_label: :login
        use :all, include: %i[dns_zone dns_zone_name change_type name type]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u, dns_zones: { user_id: u.id }
        input whitelist: %i[dns_zone change_type name type from_id limit]
        output blacklist: %i[user]
        allow
      end

      def query
        q = self.class.model.joins(:dns_zone).where(with_restricted)

        %i[user dns_zone dns_zone_name change_type name].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q = q.where(record_type: input[:type]) if input[:type]

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query).order('created_at DESC'))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS record log'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u, dns_zones: { user_id: u.id }
        output blacklist: %i[user]
        allow
      end

      def prepare
        @log = self.class.model.joins(:dns_zone).find_by(with_restricted(id: params[:dns_record_log_id]))
      end

      def exec
        @log
      end
    end
  end
end
