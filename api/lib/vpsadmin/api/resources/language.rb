module VpsAdmin::API::Resources
  class Language < HaveAPI::Resource
    desc 'Available languages'
    model ::Language

    params(:all) do
      id :id
      string :code
      string :label
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List languages'

      output(:object_list) do
        use :all
      end

      authorize { allow }

      def query
        ::Language.all
      end

      def count
        query.count
      end

      def exec
        query.offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show language'

      output do
        use :all
      end

      authorize { allow }

      def prepare
        @lang = ::Language.find(params[:language_id])
      end

      def exec
        @lang
      end
    end
  end
end
