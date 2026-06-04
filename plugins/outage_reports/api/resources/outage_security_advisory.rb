module VpsAdmin::API::Resources
  class OutageSecurityAdvisory < HaveAPI::Resource
    desc 'Browse and manage outage security advisory links'
    model ::OutageSecurityAdvisory

    params(:editable) do
      resource VpsAdmin::API::Resources::Outage,
               value_label: :begins_at,
               desc: 'Outage linked to a security advisory.'
      resource VpsAdmin::API::Resources::SecurityAdvisory,
               value_label: :id,
               desc: 'Security advisory linked to an outage.'
    end

    params(:all) do
      id :id
      use :editable
      integer :outage_id
      integer :security_advisory_id
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List outage security advisory links'
      auth false

      input do
        use :editable
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        q = ::OutageSecurityAdvisory
            .joins(:outage, :security_advisory)
            .merge(::Outage.visible_to(current_user))
            .merge(::SecurityAdvisory.visible_to(current_user))

        q = q.where(outage: input[:outage]) if input[:outage]
        q = q.where(security_advisory: input[:security_advisory]) if input[:security_advisory]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('outage_security_advisories.id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show outage security advisory link'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @link = with_includes(
          ::OutageSecurityAdvisory
            .joins(:outage, :security_advisory)
            .merge(::Outage.visible_to(current_user))
            .merge(::SecurityAdvisory.visible_to(current_user))
        ).find(path_params['outage_security_advisory_id'])
      end

      def exec
        @link
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Link security advisory to outage'

      input do
        use :editable
        patch :outage, required: true
        patch :security_advisory, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::OutageSecurityAdvisory.create!(
          outage: input[:outage],
          security_advisory: input[:security_advisory]
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', to_param_names(e.record.errors.to_hash))
      rescue ActiveRecord::RecordNotUnique
        error!('create failed', security_advisory: ['is already linked to this outage'])
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Unlink security advisory from outage'

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @link = ::OutageSecurityAdvisory.find(path_params['outage_security_advisory_id'])
      end

      def exec
        @link.destroy!
        ok!
      end
    end
  end
end
