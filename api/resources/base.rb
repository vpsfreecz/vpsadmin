module VpsAdmin::API::Plugins::Requests
  module BaseResource
    def self.included(res)
      res.params(:common) do
        id :id
        resource VpsAdmin::API::Resources::User, value_label: :login
        string :state, choices: ::UserRequest.states.keys.map(&:to_s)
        string :api_ip_addr, label: 'API IP address'
        string :api_ip_ptr, label: 'API IP PTR'
        string :client_ip_addr, label: 'Client IP address'
        string :client_ip_ptr, label: 'Client IP PTR'
        resource VpsAdmin::API::Resources::User, name: :admin, value_label: :login
        string :admin_response, label: "Admin's response"
        datetime :created_at, label: 'Created at'
        datetime :updated_at, label: 'Updated at'
        string :label, label: 'Label'
      end

      res.params(:all) do
        use :common
        use :request
      end

      res.define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        input do
          use :common, include: %i(user state api_ip_addr client_ip_addr admin)
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          deny unless u
          allow if u.role == :admin
          restrict user_id: u.id
          input whitelist: %i(state)
          allow
        end

        def query
          q = self.class.model.where(with_restricted)
          q = q.where(state: ::UserRequest.states[input[:state]]) if input[:state]
          
          %i(user api_ip_addr client_ip_addr admin).each do |v|
            q = q.where(v =>input[v]) if input[v]
          end

          q
        end

        def count
          query.count
        end

        def exec
          with_includes(query).limit(input[:limit]).offset(input[:offset])
        end
      end
      
      res.define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
        output do
          use :all
        end

        authorize do |u|
          deny unless u
          allow if u.role == :admin
          restrict user_id: u.id
          allow
        end

        def prepare
          @req = ::UserRequest.find_by!(with_restricted(
              id: params[:"#{self.class.resource.to_s.demodulize.underscore}_id"]
          ))
        end

        def exec
          @req
        end
      end
      
      res.define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
        input do
          use :request
        end

        output do
          use :all
        end

        authorize do |u|
          allow
        end

        def exec
          self.class.model.create!(request, current_user, input)

        rescue ActiveRecord::RecordInvalid => e
          error('create failed', e.record.errors.to_hash)
        end
      end

      res.define_action(:Resolve) do
        http_method :post
        route ':%{resource}_id/resolve'
        desc 'Resolve user request'

        input do
          string :action, choices: %w(approve deny ignore request_correction), required: true
          text :reason

          use :request

          params.each do |p|
            next if %i(action reason).include?(p.name)
            p.patch(required: false)
          end

          use :resolve
        end
        
        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          r = ::UserRequest.find(
              params[:"#{self.class.resource.to_s.demodulize.underscore}_id"]
          )

          request_params = input.clone
          request_params.delete_if { |k, _| %i(action reason).include?(k) }

          r.resolve(input[:action].to_sym, input[:reason], request_params)
          ok

        rescue ActiveRecord::RecordInvalid => e
          error('unable to resolve', e.record.errors.to_hash)
        end
      end
    end
  end
end
