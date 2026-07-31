require_relative '../events/report_mute_route'

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
      resource Mailbox, nullable: true
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
                                                               id: path_params['incident_report_id']
                                                             ))
      end

      def exec
        @incident
      end
    end

    class MuteSimilar < HaveAPI::Action
      desc 'Create a mute route matching values from this incident report'
      route '{%{resource}_id}/mute_similar'
      http_method :post

      input do
        resource VpsAdmin::API::Resources::User,
                 name: :route_owner,
                 value_label: :login,
                 nullable: true
        bool :match_vps, default: false, fill: true
        bool :match_ip_addr, default: false, fill: true
        bool :match_codename, default: false, fill: true
        bool :match_subject, default: false, fill: true
        datetime :expires_at,
                 label: 'Expires at',
                 desc: 'Optional date and time after which this route stops matching events',
                 desc_key: 'vpsadmin.resources.event_route.attributes.expires_at.description',
                 nullable: true
      end

      output namespace: :event_route do
        id :id
        integer :user_id
        integer :notification_receiver_id, nullable: true
        string :label, nullable: true
        integer :position
        bool :enabled
        string :event_type, nullable: true
        string :subject_scope
        bool :grouping_enabled
        bool :continue
        bool :single_use
        datetime :spent_at, nullable: true
        datetime :expires_at,
                 label: 'Expires at',
                 desc: 'Optional date and time after which this route stops matching events',
                 desc_key: 'vpsadmin.resources.event_route.attributes.expires_at.description',
                 nullable: true
        string :matcher_summary
        integer :matcher_count
        string :display_label
        datetime :created_at
        datetime :updated_at
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @incident = with_includes(::IncidentReport).find_by!(with_restricted(
                                                               id: path_params['incident_report_id']
                                                             ))
      end

      def exec
        VpsAdmin::API::Events::ReportMuteRoute.new(
          current_user:,
          source_user: @incident.user,
          owner: input[:route_owner],
          event_type: 'vps.incident_report',
          label: "Mute incident reports like ##{@incident.id}",
          matchers: selected_matchers,
          expires_at: input[:expires_at]
        ).create!
      rescue VpsAdmin::API::Events::ReportMuteRoute::Error => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end

      protected

      def selected_matchers
        {
          match_vps: [:vps_id, @incident.vps_id],
          match_ip_addr: [:ip_addr, incident_ip_addr],
          match_codename: [:codename, @incident.codename],
          match_subject: [:subject, @incident.subject]
        }.filter_map do |input_name, (field, value)|
          { field:, value: } if input[input_name]
        end
      end

      def incident_ip_addr
        @incident.ip_address_assignment&.ip_addr || @incident.ip_address&.ip_addr
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
        @chain, = TransactionChains::IncidentReport::Utils.fire_new(incident)
        incident
      end

      def state_id
        @chain&.id
      end
    end
  end
end
