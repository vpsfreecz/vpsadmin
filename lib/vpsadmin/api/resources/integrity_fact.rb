module VpsAdmin::API::Resources
  class IntegrityFact < HaveAPI::Resource
    version 1
    desc 'View checked facts of integrity objects'
    model ::IntegrityFact

    params(:all) do
      id :id
      resource IntegrityObject, value_label: :class_name
      string :name
      custom :expected_value
      custom :actual_value
      string :status, choices: ::IntegrityFact.statuses.keys
      string :severity, choices: ::IntegrityFact.severities.keys
      string :message
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List checked facts'

      input do
        resource IntegrityCheck, value_label: :created_at
        string :class_name
        use :all, include: %i(integrity_object name status severity)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::IntegrityFact.all

        if input[:integrity_check]
          q = q.joins(:integrity_object).where(
              integrity_objects: {integrity_check_id: input[:integrity_check].id}
          )
        end
        
        if input[:class_name]
          q = q.joins(:integrity_object).where(
              integrity_objects: {class_name: input[:class_name]}
          )
        end

        q = q.where(integrity_object: input[:integrity_object]) if input[:integrity_object]
        q = q.where(name: input[:name]) if input[:name]
        q = q.where(status: ::IntegrityFact.statuses[input[:status]]) if input[:status]
        q = q.where(severity: ::IntegrityFact.severities[input[:severity]]) if input[:severity]
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
      desc 'Show a checked fact'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @fact = ::IntegrityFact.find(params[:integrity_fact_id])
      end

      def exec
        @fact
      end
    end
  end
end
