module VpsAdmin
  module API
    module Actions
      module Default
        class Index < Action
          route ''
          http_method :get
        end

        class Create < Action
          route ''
          http_method :post
        end

        class Show < Action
          route ':%{resource}_id'
          http_method :get
        end

        class Update < Action
          route ':%{resource}_id'
          http_method :put

          input do
            requires :id
          end
        end

        class Delete < Action
          route ':%{resource}_id'
          http_method :delete
        end
      end
    end
  end
end
