module VpsAdmin::API::Resources
  class Outage < HaveAPI::Resource
    desc 'Report and browse outages'
    model ::Outage
    
    params(:editable) do
      datetime :begins_at, label: 'Begins at'
      datetime :finished_at, label: 'Finished at'
      integer :duration, label: 'Duration', desc: 'Outage duration in minutes'
      bool :planned, label: 'Planned', desc: 'Is this outage planned?'
      string :state, label: 'State', choices: ::Outage.states.keys.map(&:to_s)
      string :type, db_name: :outage_type, label: 'Type',
          choices: ::Outage.outage_types.keys.map(&:to_s)

      ::Language.all.each do |lang|
        string :"#{lang.code}_summary", label: "#{lang.label} summary"
        string :"#{lang.code}_description", label: "#{lang.label} description"
      end
    end

    params(:all) do
      id :id
      use :editable
      bool :affected, label: 'Affected',
          desc: 'True if the current user is affected by the outage'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List outages'

      input do
        use :all, include: %i(planned state type affected)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow
      end

      def query
        q = ::Outage.all
        q = q.where(planned: input[:planned]) if input.has_key?(:planned)
        q = q.where(state: ::Outage.states[input[:state]]) if input[:state]
        q = q.where(outage_type: ::Outage.outage_types[input[:type]]) if input[:type]
        q
      end

      def count
        query.count
      end

      def exec
        # Fetch twice the number of requested records if filtering outages affecting
        # the current user. Imagine that the limit is 5, so we fetch 5 outages from
        # the database, but none is affecting the current user, so the response is empty.
        # However, there may be outages affecting the current user, there are just 5
        # unaffecting outages before them. Fetching twice the requested limit is not
        # solving this issue entirely, but makes it less likely.
        ret = with_includes(query)
            .limit((input[:limit] && input.has_key?(:affected)) ? input[:limit]*2 : input[:limit])
            .offset(input[:offset])
            .order('begins_at, created_at')

        if input.has_key?(:affected)
          ret.to_a.select { |v| input[:affected] === v.affected }
        else
          ret
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show outage details'

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        @outage = ::Outage.find(params[:outage_id])
      end

      def exec
        @outage
      end
    end

    class Create < HaveAPI::Actions::Default::Create
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
        # Separate translations from other parameters
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

        ::Outage.create!(to_db_names(input), tr)

      rescue ActiveRecord::RecordInvalid => e
        error('report failed', to_param_names(e.record.errors.to_hash))
      end
    end
    
    class Update < HaveAPI::Actions::Default::Update
      desc 'Update an outage'
      blocking true

      input do
        use :editable, exclude: %i(planned)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        outage = ::Outage.find(params[:outage_id])

        # Separate translations from other parameters
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

        @chain, ret = outage.update!(to_db_names(input), tr)
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

        @chain, ret = outage.announce!
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class Close < HaveAPI::Action
      desc 'Close the outage, indicating that it is over'
      http_method :post
      route ':%{resource}_id/close'
      blocking true

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end
      
      def exec
        outage = ::Outage.find(params[:outage_id])
        @chain, ret = outage.close!
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end

    class Cancel < HaveAPI::Action
      desc 'Cancel scheduled outage'
      http_method :post
      route ':%{resource}_id/cancel'
      blocking true

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

        @chain, ret = outage.cancel!
        ret
      end

      def state_id
        @chain.empty? ? nil : @chain.id
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
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List outage entities'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow
        end

        def query
          ::OutageEntity.all
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
        string :note
      end

      params(:all) do
        id :id
        use :editable
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List outage entities'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow
        end

        def query
          ::OutageHandler.all
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

        output do
          use :all
        end

        authorize do |u|
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
