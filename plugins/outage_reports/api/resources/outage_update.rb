require_relative 'outage'

module VpsAdmin::API::Resources
  class OutageUpdate < HaveAPI::Resource
    desc 'Browse outage updates'
    model ::OutageUpdate

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
      string :state, label: 'State', choices: ::OutageUpdate.states.keys.map(&:to_s)
      string :impact, db_name: :impact_type, label: 'Impact',
                      choices: ::OutageUpdate.impact_types.keys.map(&:to_s)
      use :texts
    end

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      string :type, db_name: :outage_type, label: 'Type', choices: ::Outage.outage_types.keys.map(&:to_s)
      use :editable
      resource VpsAdmin::API::Resources::User, name: :reported_by, value_label: :login,
                                               label: 'Reported by'
      string :reporter_name, label: "Reporter's name"
      datetime :created_at, label: 'Reported at'
    end

    params(:filters) do
      use :all, include: %i[outage reported_by]
      datetime :since, label: 'Since', desc: 'Filter updates reported since specified date'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List outage updates'
      auth false

      input do
        use :filters
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i[user]
        allow
      end

      def query
        q = ::OutageUpdate.includes(:outage).all

        if current_user.nil? || current_user.role != :admin
          q = q.where('state != ? OR state is NULL', ::Outage.states[:staged])
        end

        q = q.where(outage: input[:outage]) if input[:outage]
        q = q.where(reported_by: input[:reported_by]) if input[:reported_by]
        q = q.where('created_at > ?', input[:since]) if input[:since]
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset]).order('created_at')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show outage update'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i[user]
        allow
      end

      def prepare
        q = ::OutageUpdate.includes(:outage).where(id: params[:outage_update_id])

        if current_user.nil? || current_user.role != :admin
          q = q.where('state != ? OR state is NULL', ::Outage.states[:staged])
        end

        @outage = q.take!
      end

      def exec
        @outage
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include VpsAdmin::API::Resources::Outage::Helpers

      desc 'Create outage update'
      blocking true

      input do
        resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
        use :editable
        bool :send_mail, label: 'Send mail', default: true, fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
      end

      def exec
        outage = input.delete(:outage)
        tr = extract_translations
        opts = { send_mail: input.delete(:send_mail) }

        if input[:state]
          if input[:state] == outage.state
            error('update failed', { state: ["is already #{outage.state}"] })

          elsif input[:state] == 'announced'
            if outage.state != 'staged'
              error('Only staged outages can be announced')

            elsif outage.outage_handlers.count <= 0
              error('Add at least one outage handler')

            elsif outage.outage_entities.count <= 0
              error('Add at least one entity impaired by the outage')
            end
          end
        end

        @chain, ret = outage.create_outage_update!(to_db_names(input), tr, opts)
        ret
      rescue ActiveRecord::RecordInvalid => e
        error('update failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @chain.empty? ? nil : @chain.id
      end
    end
  end
end
