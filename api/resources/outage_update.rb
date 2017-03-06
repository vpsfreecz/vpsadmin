module VpsAdmin::API::Resources
  class OutageUpdate < HaveAPI::Resource
    desc 'Browse outage updates'
    model ::OutageUpdate

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      datetime :begins_at, label: 'Begins at'
      datetime :finished_at, label: 'Finished at'
      integer :duration, label: 'Duration', desc: 'Outage duration in minutes'
      string :state, label: 'State', choices: ::Outage.states.keys.map(&:to_s)
      string :type, db_name: :outage_type, label: 'Type',
          choices: ::Outage.outage_types.keys.map(&:to_s)

      ::Language.all.each do |lang|
        string :"#{lang.code}_summary", label: "#{lang.label} summary"
        string :"#{lang.code}_description", label: "#{lang.label} description"
      end

      resource VpsAdmin::API::Resources::User, name: :reported_by, value_label: :login,
          label: 'Reported by'
      string :reporter_name, label: "Reporter's name"
      datetime :created_at, label: 'Reported at'
    end

    params(:filters) do
      use :all, include: %i(outage reported_by)
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
        output blacklist: %i(user)
        allow
      end

      def query
        q = ::OutageUpdate.all

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
        output blacklist: %i(user)
        allow
      end

      def prepare
        q = ::OutageUpdate.where(id: params[:outage_update_id])

        if current_user.nil? || current_user.role != :admin
          q = q.where('state != ? OR state is NULL', ::Outage.states[:staged])
        end

        @outage = q.take!
      end

      def exec
        @outage
      end
    end
  end
end
