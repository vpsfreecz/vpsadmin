module VpsAdmin::API::Resources
  class DnssecRecord < HaveAPI::Resource
    model ::DnssecRecord
    desc 'View DNSSEC DNSKEY/DS records'

    params(:all) do
      integer :id, label: 'ID'
      resource DnsZone, value_label: :name
      integer :keyid, label: 'Key ID'
      integer :dnskey_algorithm, label: 'DNSKEY algorithm'
      string :dnskey_pubkey, label: 'DNSKEY public key'
      integer :ds_algorithm, label: 'DS algorithm'
      integer :ds_digest_type, label: 'DS digest type'
      string :ds_digest, label: 'DS digest'
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNSSEC records'

      input do
        use :all, include: %i[dns_zone]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        input whitelist: %i[dns_zone]
        allow
      end

      def query
        q = self.class.model.joins(:dns_zone).where(with_restricted)

        %i[dns_zone].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

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
      desc 'Show DNSSEC record'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      def prepare
        @record = self.class.model.joins(:dns_zone).find_by!(with_restricted(id: params[:dnssec_record_id]))
      end

      def exec
        @record
      end
    end
  end
end
