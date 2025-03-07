module VpsAdmin::API::Resources
  class IncidentReport < HaveAPI::Resource
    model ::IncidentReport
    desc 'Manage incident reports'

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      resource User, value_label: :login
      resource VPS, value_label: :hostname
      resource IpAddressAssignment, value_label: :ip_addr, label: 'IP address assignment'
      resource User, name: :filed_by, value_label: :login
      resource Mailbox
      string :subject
      text :text
      string :codename
      integer :cpu_limit, label: 'CPU limit'
      string :vps_action, label: 'VPS action', choices: ::IncidentReport.vps_actions.keys.map(&:to_s),
                          default: 'none', fill: true
    end

    params(:all) do
      use :id
      use :common
      integer :raw_user_id
      integer :raw_vps_id
      datetime :detected_at
      datetime :created_at
      datetime :reported_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List incident reports'

      input do
        use :common, include: %i[user vps ip_address_assignment filed_by mailbox codename]
        string :ip_addr, label: 'IP address'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user mailbox]
        allow
      end

      def query
        q = ::IncidentReport.where(with_restricted)

        %i[user vps ip_address_assignment filed_by mailbox codename].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        if input[:ip_addr]
          q = q.joins(:ip_address_assignment).where(
            ip_address_assignments: { ip_addr: input[:ip_addr] }
          )

          if current_user.role != :admin
            q = q.where(
              ip_address_assignments: { user_id: current_user.id }
            )
          end
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_desc_pagination(with_includes(query).order('detected_at DESC'))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show incident report'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user mailbox]
        allow
      end

      def prepare
        @incident = with_includes(::IncidentReport).find_by!(with_restricted(
                                                               id: params[:incident_report_id]
                                                             ))
      end

      def exec
        @incident
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create incident report'
      blocking true

      input do
        use :all, include: %i[vps ip_address_assignment subject text codename detected_at cpu_limit vps_action]

        %i[vps subject text].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        incident = ::IncidentReport.create!(
          user: input[:vps].user,
          vps: input[:vps],
          ip_address_assignment: input[:ip_address_assignment],
          filed_by: current_user,
          subject: input[:subject],
          text: input[:text],
          codename: input[:codename],
          detected_at: input[:detected_at] || Time.now,
          cpu_limit: input[:cpu_limit],
          vps_action: input[:vps_action]
        )
        @chain, = TransactionChains::IncidentReport::New.fire2(
          args: [incident]
        )
        incident
      end

      def state_id
        @chain.id
      end
    end
  end
end
