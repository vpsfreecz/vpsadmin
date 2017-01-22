module VpsAdmin::API::Plugins::Requests
  module BaseResource
    def self.included(klass)
      klass.constants.each do |v|
        res = klass.const_get(v)
        next if !res.respond_to?(:obj_type) || res.obj_type != :resource

        res.params(:common) do
          id :id
          resource VpsAdmin::API::Resources::User, value_label: :login
          string :state, choices: ::UserRequest.states.keys.map(&:to_s)
          string :ip_addr
          string :ip_addr_ptr
          resource VpsAdmin::API::Resources::User, name: :admin, value_label: :login
          string :admin_response
          datetime :created_at
          datetime :updated_at
        end

        res.params(:all) do
          use :common
          use :request
        end

        res.define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
          input do
            use :common, exclude: %i(id)
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
            # TODO: other filters
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
      end
    end
  end
end
