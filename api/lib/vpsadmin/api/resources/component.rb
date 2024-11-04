module VpsAdmin::API::Resources
  class Component < HaveAPI::Resource
    model ::Component
    desc 'Browse vpsAdmin components'
    auth false

    params(:all) do
      id :id
      string :name
      string :label
      text :description
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List vpsAdmin components'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        self.class.model.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show vpsAdmin component'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @component = self.class.model.find(params[:component_id])
      end

      def exec
        @component
      end
    end
  end
end
