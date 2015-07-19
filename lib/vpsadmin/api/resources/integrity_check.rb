module VpsAdmin::API::Resources
  class IntegrityCheck < HaveAPI::Resource
    version 1
    desc 'Schedule integrity checks and view results'
    model ::IntegrityCheck

    params(:input) do
      resource Node
      bool :storage
    end

    params(:all) do
      id :id
      string :status, choices: ::IntegrityCheck.statuses
      resource User, value_label: :login
      integer :checked_objects
      integer :integral_objects
      integer :broken_objects
      integer :checked_facts
      integer :true_facts
      integer :false_facts
      datetime :created_at
      datetime :updated_at
      datetime :finished_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List integrity checks'

      input do
        use :all, include: %i(status user)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::IntegrityCheck.all
        q = q.where(status: ::IntegrityCheck.statuses[input[:status]]) if input[:status]
        q = q.where(user: input[:user]) if input[:user]
        q
      end

      def count
        q.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show an integrity check'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @check = ::IntegrityCheck.find(params[:integrity_check_id])
      end

      def exec
        @check
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Schedule a new cluster-wide integrity check'

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
        ::IntegrityCheck.schedule(input)
      end
    end
  end
end
