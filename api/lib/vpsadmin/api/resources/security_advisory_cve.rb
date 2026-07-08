module VpsAdmin::API::Resources
  class SecurityAdvisoryCve < HaveAPI::Resource
    desc 'Browse and manage security advisory CVEs'
    model ::SecurityAdvisoryCve

    params(:editable) do
      resource VpsAdmin::API::Resources::SecurityAdvisory,
               label: 'Security advisory',
               value_label: :id,
               desc: 'Advisory to which this CVE belongs.'
      string :cve_id,
             label: 'CVE',
             desc: 'CVE identifier in CVE-YYYY-NNNN format, ' \
                   'e.g. CVE-2026-12345.'
    end

    params(:all) do
      id :id
      use :editable
      integer :security_advisory_id, label: 'Security advisory ID'
      string :url, label: 'URL'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List security advisory CVEs'
      auth false

      input do
        resource VpsAdmin::API::Resources::SecurityAdvisory,
                 label: 'Security advisory',
                 value_label: :id,
                 desc: 'Filter CVEs assigned to this advisory.'
        string :cve, label: 'CVE', desc: 'Filter by CVE identifier.'
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        q = ::SecurityAdvisoryCve
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))

        q = q.where(security_advisory: input[:security_advisory]) if input[:security_advisory]
        q = q.where(cve_id: ::SecurityAdvisory.normalize_cve(input[:cve])) if input[:cve]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('security_advisory_cves.cve_id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show security advisory CVE'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @cve = with_includes(
          ::SecurityAdvisoryCve
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))
        ).find(path_params['security_advisory_cve_id'])
      end

      def exec
        @cve
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add CVE to security advisory'

      input do
        use :editable
        patch :security_advisory, required: true
        patch :cve_id, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::SecurityAdvisoryCve.create!(
          security_advisory: input[:security_advisory],
          cve_id: input[:cve_id]
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update security advisory CVE'

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        cve = ::SecurityAdvisoryCve.find(path_params['security_advisory_cve_id'])
        attrs = {}
        attrs[:security_advisory] = input[:security_advisory] if input.has_key?(:security_advisory)
        attrs[:cve_id] = input[:cve_id] if input.has_key?(:cve_id)
        cve.update!(attrs)
        cve
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Remove CVE from security advisory'

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @cve = ::SecurityAdvisoryCve.find(path_params['security_advisory_cve_id'])
      end

      def exec
        @cve.destroy!
        ok!
      end
    end
  end
end
