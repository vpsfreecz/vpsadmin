module VpsAdmin::API::Resources
  class IntegrityObject < HaveAPI::Resource
    version 1
    desc 'View objects whose integrity is checked'
    model ::IntegrityObject

    params(:all) do
      id :id
      resource IntegrityCheck, value_label: :created_at
      string :class_name
      integer :row_id
      resource IntegrityObject, name: :parent, value_label: :class_name
      string :status, choices: ::IntegrityObject.statuses
      integer :checked_facts
      integer :true_facts
      integer :false_facts
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List integrity objects'

      input do
        use :all, include: %i(integrity_check parent status)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::IntegrityObject.all
        q = q.where(integrity_check: input[:integrity_check]) if input[:integrity_check]
        q = q.where(integrity_object: input[:parent]) if input[:parent]
        q = q.where(status: ::IntegrityObject.statuses[input[:status]]) if input[:status]
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
      desc 'Show an integrity object'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @obj = ::IntegrityObject.find(params[:integrity_object_id])
      end

      def exec
        @obj
      end
    end
  end
end
