module VpsAdmin::API::Resources
  class SecurityAdvisory < HaveAPI::Resource
    desc 'Report and browse security advisories'
    model ::SecurityAdvisory

    NAME_DESCRIPTION = 'Optional well-known vulnerability name, e.g. Dirty Pipe.'.freeze
    PUBLISHED_AT_DESCRIPTION =
      'Date and time shown as the advisory publication time.'.freeze
    SEND_MAIL_DESCRIPTION =
      'When enabled, affected users are emailed after the action completes.'.freeze
    TEXT_DESCRIPTIONS = {
      summary: 'One-sentence public summary shown in advisory lists, ' \
               'status output, IRC announcements, and emails.',
      description: 'User-facing explanation of the vulnerability, ' \
                   'affected systems, impact, and conditions.',
      response: 'User-facing explanation of the mitigation or fix ' \
                'and whether users need to take action.'
    }.freeze

    NON_ADMIN_OUTPUT_BLACKLIST = %i[
      affected_user_count
      affected_vps_count
      created_by
      published_by
    ].freeze

    params(:texts) do
      ::Language.all.each do |lang|
        string :"#{lang.code}_summary",
               label: "#{lang.label} summary",
               desc: TEXT_DESCRIPTIONS[:summary]
        text :"#{lang.code}_description",
             label: "#{lang.label} description",
             desc: TEXT_DESCRIPTIONS[:description]
        text :"#{lang.code}_response",
             label: "#{lang.label} response",
             desc: TEXT_DESCRIPTIONS[:response]
      end
    end

    params(:editable) do
      string :name, label: 'Name', desc: NAME_DESCRIPTION, nullable: true
      datetime :published_at,
               label: 'Published at',
               desc: PUBLISHED_AT_DESCRIPTION,
               nullable: true
      use :texts
    end

    params(:all) do
      id :id
      string :state, choices: ::SecurityAdvisory.states.keys.map(&:to_s)
      use :editable
      bool :affected,
           label: 'Affected',
           desc: 'True if the current user is affected by the advisory'
      integer :affected_node_count, label: 'Affected nodes'
      integer :affected_user_count, label: 'Affected users'
      integer :affected_vps_count, label: 'Affected VPSes'
      resource VpsAdmin::API::Resources::User,
               name: :created_by,
               value_label: :login,
               nullable: true
      resource VpsAdmin::API::Resources::User,
               name: :published_by,
               value_label: :login,
               nullable: true
      datetime :published_at, desc: PUBLISHED_AT_DESCRIPTION, nullable: true
      datetime :retracted_at, nullable: true
      datetime :created_at
      datetime :updated_at
    end

    module Helpers
      def extract_translations
        tr = {}

        ::Language.all.each do |lang|
          %i[summary description response].each do |param|
            name = :"#{lang.code}_#{param}"

            if input.has_key?(name)
              tr[lang] ||= {}
              tr[lang][param] = input.delete(name)
            end
          end
        end

        tr
      end
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List security advisories'
      auth false

      input do
        use :all, include: %i[state affected]
        string :cve, label: 'CVE'
        datetime :recent_since, desc: 'Filter published or recently updated advisories'
        resource VpsAdmin::API::Resources::User, name: :user, label: 'User'
        resource VpsAdmin::API::Resources::VPS, name: :vps, label: 'VPS'
        resource VpsAdmin::API::Resources::Node, name: :node, label: 'Node'
        datetime :since, label: 'Since', desc: 'Filter advisories created since specified date'
        string :order, label: 'Order', choices: %w[newest oldest], default: 'newest', fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: NON_ADMIN_OUTPUT_BLACKLIST
        input blacklist: %i[user]
        allow if u
        input blacklist: %i[affected user vps]
        allow
      end

      def query
        q = ::SecurityAdvisory.visible_to(current_user)

        q = q.where(state: ::SecurityAdvisory.states[input[:state]]) if input[:state]

        if input[:cve]
          q = q.joins(:security_advisory_cves).where(
            security_advisory_cves: { cve_id: ::SecurityAdvisory.normalize_cve(input[:cve]) }
          )
        end

        if input[:affected]
          q = q.joins(:security_advisory_users).where(
            security_advisory_users: { user_id: current_user.id }
          )
        elsif input.has_key?(:affected)
          q = q.where.not(
            id: ::SecurityAdvisoryUser.where(user_id: current_user.id).select(:security_advisory_id)
          )
        end

        if input[:recent_since]
          q = q.where(
            'state IN (?) AND (published_at >= ? OR updated_at >= ?)',
            [::SecurityAdvisory.states[:published], ::SecurityAdvisory.states[:retracted]],
            input[:recent_since],
            input[:recent_since]
          )
        end

        if input[:user]
          q = q.joins(:security_advisory_users).where(
            security_advisory_users: { user_id: input[:user].id }
          )
        end

        if input[:vps]
          q = q.joins(:security_advisory_vpses).where(
            security_advisory_vpses: { vps_id: input[:vps].id }
          )
          unless current_user.role == :admin
            q = q.where(security_advisory_vpses: { user_id: current_user.id })
          end
        end

        if input[:node]
          q = q.joins(:security_advisory_node_statuses).where(
            security_advisory_node_statuses: { node_id: input[:node].id }
          )
        end

        q = q.where('security_advisories.created_at > ?', input[:since]) if input[:since]
        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query)

        case input[:order]
        when 'oldest'
          with_asc_pagination(q).order('published_at, created_at')
        else
          with_desc_pagination(q).order('published_at DESC, created_at DESC')
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show security advisory details'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: NON_ADMIN_OUTPUT_BLACKLIST
        allow
      end

      def prepare
        @advisory = with_includes(::SecurityAdvisory.visible_to(current_user)).find(path_params['security_advisory_id'])
      end

      def exec
        @advisory
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include Helpers

      desc 'Create security advisory draft'

      input do
        use :editable

        ::Language.all.each do |lang|
          patch :"#{lang.code}_summary", required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tr = extract_translations
        ::SecurityAdvisory.transaction do
          advisory = ::SecurityAdvisory.create!(to_db_names(input).merge(created_by: current_user))
          advisory.update_translations!(tr)
          advisory
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include Helpers

      desc 'Update security advisory draft metadata'

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
        advisory = ::SecurityAdvisory.find(path_params['security_advisory_id'])
        tr = extract_translations
        ::SecurityAdvisory.transaction do
          advisory.update!(to_db_names(input))
          advisory.update_translations!(tr)
          advisory
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Publish < HaveAPI::Action
      desc 'Publish security advisory'
      route '{%{resource}_id}/publish'
      http_method :post
      blocking true

      input do
        bool :send_mail,
             label: 'Send mail',
             desc: SEND_MAIL_DESCRIPTION,
             default: false,
             fill: true
        datetime :published_at,
                 label: 'Published at',
                 desc: PUBLISHED_AT_DESCRIPTION,
                 nullable: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        @advisory = ::SecurityAdvisory.find(path_params['security_advisory_id'])
        @advisory.publish!(
          send_mail: input[:send_mail],
          published_by: current_user,
          published_at: input[:published_at]
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('publish failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @advisory&.last_chain&.id
      end
    end

    class RebuildAffectedVps < HaveAPI::Action
      desc 'Rebuild affected VPS snapshot'
      route '{%{resource}_id}/rebuild_affected_vps'
      http_method :post

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::SecurityAdvisory.find(path_params['security_advisory_id']).rebuild_affected!
        ok!
      end
    end

    class NodeStatus < HaveAPI::Resource
      desc 'Security advisory node statuses'
      route '{security_advisory_id}/node_statuses'
      model ::SecurityAdvisoryNodeStatus

      params(:editable) do
        resource VpsAdmin::API::Resources::Node,
                 value_label: :domain_name,
                 desc: 'Node whose exposure status is being recorded.'
        string :state,
               choices: ::SecurityAdvisoryNodeStatus.states.keys.map(&:to_s),
               desc: 'Assessment of whether the node was affected ' \
                     'and whether it has been mitigated.'
        datetime :vulnerable_until,
                 desc: 'When vulnerability exposure ended on this node, if known.',
                 nullable: true
        datetime :mitigated_since,
                 desc: 'When the node was mitigated or patched, if known.',
                 nullable: true
        text :note, desc: 'Optional operator note for this node status.', nullable: true
      end

      params(:all) do
        id :id
        resource VpsAdmin::API::Resources::SecurityAdvisory,
                 label: 'Security advisory',
                 value_label: :id
        integer :node_id
        string :node_name
        string :state,
               choices: ::SecurityAdvisoryNodeStatus.states.keys.map(&:to_s),
               desc: 'Assessment of whether the node was affected ' \
                     'and whether it has been mitigated.'
        datetime :vulnerable_until,
                 desc: 'When vulnerability exposure ended on this node, if known.',
                 nullable: true
        datetime :mitigated_since,
                 desc: 'When the node was mitigated or patched, if known.',
                 nullable: true
        text :note, desc: 'Optional operator note for this node status.', nullable: true
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List advisory node statuses'
        auth false

        input do
          use :editable, include: %i[node state]
        end

        output(:object_list) do
          use :all
        end

        authorize do |_u|
          allow
        end

        def query
          ::SecurityAdvisoryNodeStatus
            .joins(:node)
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))
            .where(security_advisory_id: path_params['security_advisory_id'])
        end

        def count
          query.count
        end

        def exec
          q = with_includes(query.includes(:node)).order('nodes.id')
          q = q.where(node: input[:node]) if input[:node]
          q = q.where(state: ::SecurityAdvisoryNodeStatus.states[input[:state]]) if input[:state]
          with_pagination(q)
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create advisory node status'

        input do
          use :editable
          patch :node, required: true
          patch :state, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          advisory = ::SecurityAdvisory.find(path_params['security_advisory_id'])
          ::SecurityAdvisoryNodeStatus.create!(
            to_db_names(input).merge(security_advisory: advisory)
          )
        rescue ActiveRecord::RecordInvalid => e
          error!('create failed', to_param_names(e.record.errors.to_hash))
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update advisory node status'

        input do
          use :editable, exclude: %i[node]
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          status = ::SecurityAdvisoryNodeStatus.find_by!(
            security_advisory_id: path_params['security_advisory_id'],
            id: path_params['node_status_id']
          )
          status.update!(to_db_names(input))
          status
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', to_param_names(e.record.errors.to_hash))
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete advisory node status'

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @status = ::SecurityAdvisoryNodeStatus.find_by!(
            security_advisory_id: path_params['security_advisory_id'],
            id: path_params['node_status_id']
          )
        end

        def exec
          @status.destroy!
          ok!
        end
      end
    end
  end
end
