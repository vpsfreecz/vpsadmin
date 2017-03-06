module VpsAdmin::API::Resources
  class Outage < HaveAPI::Resource
    desc 'Report and browse outages'
    model ::Outage

    params(:texts) do
      ::Language.all.each do |lang|
        string :"#{lang.code}_summary", label: "#{lang.label} summary"
        string :"#{lang.code}_description", label: "#{lang.label} description"
      end
    end

    params(:editable) do
      datetime :begins_at, label: 'Begins at'
      datetime :finished_at, label: 'Finished at'
      integer :duration, label: 'Duration', desc: 'Outage duration in minutes'
      bool :planned, label: 'Planned', desc: 'Is this outage planned?'
      string :state, label: 'State', choices: ::Outage.states.keys.map(&:to_s)
      string :type, db_name: :outage_type, label: 'Type',
          choices: ::Outage.outage_types.keys.map(&:to_s)
      use :texts
    end

    params(:all) do
      id :id
      use :editable
      bool :affected, label: 'Affected',
          desc: 'True if the current user is affected by the outage'
      integer :affected_user_count, label: 'Affected users', desc: 'Number of affected users'
      integer :affected_vps_count, label: 'Affected VPSes', desc: 'Number of affected VPSes'
    end

    params(:input) do
      bool :send_mail, label: 'Send mail', default: true, fill: true
    end

    module Helpers
      def extract_translations
        tr = {}

        ::Language.all.each do |lang|
          %i(summary description).each do |param|
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
      desc 'List outages'
      auth false

      input do
        use :all, include: %i(planned state type affected)
        bool :active, label: 'Active', desc: 'Include only currently active/planned outages'
        resource VpsAdmin::API::Resources::User, name: :user, label: 'User',
            desc: 'Filter outages affecting a specific user'
        resource VpsAdmin::API::Resources::VPS, name: :vps, label: 'VPS',
            desc: 'Filter outages affecting a specific VPS'
        resource VpsAdmin::API::Resources::User, name: :handled_by, label: 'Handled by',
            desc: 'Filter outages handled by user'
        resource VpsAdmin::API::Resources::Environment,
            desc: 'Filter outages by environment'
        resource VpsAdmin::API::Resources::Location,
            desc: 'Filter outages by location'
        resource VpsAdmin::API::Resources::Node,
            desc: 'Filter outages by node'
        string :entity_name, label: 'Entity name', desc: 'Filter outages by entity name'
        integer :entity_id, label: 'Entity ID', desc: 'Filter outages by entity ID'
        string :order, label: 'Order', choices: %w(newest oldest), default: 'newest',
            fill: true
        datetime :since, label: 'Since', desc: 'Filter outages reported since specified date'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i(affected_user_count affected_vps_count)
        allow if u
        input blacklist: %i(affected user handled_by)
        allow
      end

      def query
        q = ::Outage.all

        if current_user.nil? || current_user.role != :admin
          q = q.where.not(state: ::Outage.states[:staged])
        end

        q = q.where(planned: input[:planned]) if input.has_key?(:planned)
        q = q.where(state: ::Outage.states[input[:state]]) if input[:state]
        q = q.where(outage_type: ::Outage.outage_types[input[:type]]) if input[:type]

        if input.has_key?(:affected)
          q = q.joins(:outage_vpses).group('outages.id')

          if input[:affected]
            q = q.where(
                user_id: current_user.id,
            )

          else
            q = q.where("
                outages.id NOT IN (
                  SELECT outage_id
                  FROM outage_vpses
                  WHERE user_id = ?
                )
            ", current_user.id)
          end
        end

        if input[:active]
          q = q.where(state: ::Outage.states[:announced])
          q = q.where("
              (
                DATE_ADD(begins_at, INTERVAL duration+30 MINUTE) > UTC_TIMESTAMP()
                AND finished_at IS NULL
              )
              OR finished_at > UTC_TIMESTAMP()

          ")
        end

        if input[:user]
          q = q.joins(:outage_vpses).group('outages.id').where(
              user: input[:user],
          )
        end

        if input[:vps]
          q = q.joins(:outage_vpses).group('outages.id').where(
              outage_vpses: {vps_id: input[:vps].id}
          )
        end

        if input[:handled_by]
          q = q.joins(:outage_handlers).group('outages.id').where(
              outage_handlers: {user_id: input[:handled_by].id}
          )
        end

        %i(environment location node).each do |ent|
          next unless input[ent]

          q = q.joins(:outage_entities).group('outages.id').where(
            outage_entities: {name: input[ent].class.name, row_id: input[ent].id}
          )
        end

        if input[:entity_name]
          q = q.joins(:outage_entities).group('outages.id').where(
            outage_entities: {name: input[:entity_name]}
          )
        end

        if input[:entity_id]
          q = q.joins(:outage_entities).group('outages.id').where(
            outage_entities: {row_id: input[:entity_id]}
          )
        end

        q = q.where('created_at > ?', input[:since]) if input[:since]
        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query)
            .limit(input[:limit])
            .offset(input[:offset])

        case input[:order]
        when 'oldest'
          q.order('begins_at, created_at')

        when 'newest'
          q.order('begins_at DESC, created_at DESC')
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show outage details'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i(affected_user_count affected_vps_count)
        allow if u
        input blacklist: %i(affected)
        allow
      end

      def prepare
        q = ::Outage.where(id: params[:outage_id])

        if current_user.nil? || current_user.role != :admin
          q = q.where.not(state: ::Outage.states[:staged])
        end

        @outage = q.take!
      end

      def exec
        @outage
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include Helpers

      desc 'Stage a new outage'

      input do
        use :editable, exclude: %i(state)

        %i(begins_at duration planned type).each { |p| patch p, required: true }
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tr = extract_translations
        ::Outage.create!(to_db_names(input), tr)

      rescue ActiveRecord::RecordInvalid => e
        error('report failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include Helpers

      desc 'Update an outage'
      blocking true

      input do
        use :editable, exclude: %i(planned)
        use :input
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])

        tr = extract_translations
        opts = {send_mail: input.delete(:send_mail)}

        @chain, ret = outage.update!(to_db_names(input), tr, opts)
        ret

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class Announce < HaveAPI::Action
      desc 'Publicly announce the outage'
      http_method :post
      route ':%{resource}_id/announce'
      blocking true

      input do
        use :input
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])

        if outage.state != 'staged'
          error('Only staged outages can be announced')

        elsif outage.outage_handlers.count <= 0
          error('Add at least one outage handler')

        elsif outage.outage_entities.count <= 0
          error('Add at least one entity impaired by the outage')
        end

        @chain, ret = outage.announce!({send_mail: input.delete(:send_mail)})
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class Close < HaveAPI::Action
      include Helpers

      desc 'Close the outage, indicating that it is over'
      http_method :post
      route ':%{resource}_id/close'
      blocking true

      input do
        use :texts
        use :input
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])
        tr = extract_translations
        opts = {send_mail: input.delete(:send_mail)}
        @chain, ret = outage.close!(tr, opts)
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class Cancel < HaveAPI::Action
      include Helpers

      desc 'Cancel scheduled outage'
      http_method :post
      route ':%{resource}_id/cancel'
      blocking true

      input do
        use :texts
        use :input
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])

        if outage.state == 'closed'
          error('cannot cancel a closed outage')
        end

        tr = extract_translations
        opts = {send_mail: input.delete(:send_mail)}
        @chain, ret = outage.cancel!(tr, opts)
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class RebuildAffectedVps < HaveAPI::Action
      desc 'Rebuilt the list of affected vpses, use after changing affected entities'
      http_method :post
      route ':%{resource}_id/rebuild_affected_vps'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])
        outage.set_affected_vpses
        ok
      end
    end

    class Entity < HaveAPI::Resource
      desc 'Outage entities'
      model ::OutageEntity
      route ':outage_id/entities'

      params(:editable) do
        string :name
        integer :entity_id, db_name: :row_id
      end

      params(:all) do
        id :id
        use :editable
        string :label, label: 'Label'
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List outage entities'
        auth false

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow
        end

        def query
          ::OutageEntity.where(outage_id: params[:outage_id])
        end

        def count
          query.count
        end

        def exec
          query.limit(input[:limit]).offset(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show an outage entity'
        auth false

        output do
          use :all
        end

        authorize do |u|
          allow
        end

        def prepare
          @entity = ::OutageEntity.find_by!(
              outage_id: params[:outage_id],
              id: params[:entity_id],
          )
        end

        def exec
          @entity
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add a new outage entity'

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
          ::OutageEntity.create!(
              outage: ::Outage.find(params[:outage_id]),
              name: input[:name],
              row_id: input[:entity_id],
          )

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', to_param_names(e.record.errors.to_hash))

        rescue ActiveRecord::RecordNotUnique
          error('this outage entity already exists')
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Remove an outage entity'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::OutageEntity.find_by!(
              outage_id: params[:outage_id],
              id: params[:entity_id],
          ).destroy!
          ok
        end
      end
    end

    class Handler < HaveAPI::Resource
      desc 'Outage handlers'
      model ::OutageHandler
      route ':outage_id/handlers'

      params(:editable) do
        resource VpsAdmin::API::Resources::User, value_label: :login
        string :full_name, label: 'Full name'
        string :note
      end

      params(:all) do
        id :id
        use :editable
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List outage entities'
        auth false

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u && u.role == :admin
          output blacklist: %i(user)
          allow
        end

        def query
          ::OutageHandler.where(outage_id: params[:outage_id])
        end

        def count
          query.count
        end

        def exec
          query.limit(input[:limit]).offset(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show an outage handler'
        auth false

        output do
          use :all
        end

        authorize do |u|
          allow if u && u.role == :admin
          output blacklist: %i(user)
          allow
        end

        def prepare
          @handler = ::OutageHandler.find_by!(
              outage_id: params[:outage_id],
              id: params[:handler_id],
          )
        end

        def exec
          @handler
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add a new outage handler'

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
          ::OutageHandler.create!(
              outage: ::Outage.find(params[:outage_id]),
              user: input[:user],
              note: input[:note],
          )

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', e.record.errors.to_hash)

        rescue ActiveRecord::RecordNotUnique
          error('this outage handler already exists')
        end
      end

      class Update < HaveAPI::Actions::Default::Create
        desc 'Update an outage handler'

        input do
          use :editable, include: %i(note)
          patch :note, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::OutageHandler.find_by!(
              outage_id: ::Outage.find(params[:outage_id]),
              id: params[:handler_id],
          ).update!(note: input[:note])

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', e.record.errors.to_hash)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Remove an outage handler'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::OutageHandler.find_by!(
              outage_id: params[:outage_id],
              id: params[:handler_id],
          ).destroy!
          ok
        end
      end
    end
  end
end
