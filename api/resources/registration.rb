module VpsAdmin::API::Resources
  class UserRequest
    class Registration < HaveAPI::Resource
      desc 'Request account registration'
      model ::RegistrationRequest

      params(:request) do
        string :login, label: 'Login', required: true
        string :full_name, label: 'Full name', required: true
        string :org_name, label: 'Organization name'
        string :org_id, label: 'Organization ID'
        string :email, label: 'E-mail', required: true
        text :address, label: 'Address', required: true
        integer :year_of_birth, label: 'Year of birth', required: true
        string :how, label: 'How did you learn about us?'
        string :note, label: 'Notes'
        resource VpsAdmin::API::Resources::OsTemplate, label: 'Distribution', required: true
        resource VpsAdmin::API::Resources::Location, label: 'Location', required: true
        string :currency, label: 'Currency', required: true,
            choices: ::SysConfig.get(:plugin_requests, :currencies).split(',')
        resource VpsAdmin::API::Resources::Language, label: 'Language', required: true
      end

      params(:resolve) do
        resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :domain_name,
            desc: 'Create the new VPS on this node'
        bool :create_vps, label: 'Create VPS', default: true, fill: true
      end
      
      include VpsAdmin::API::Plugins::Requests::BaseResource

      class Create
        auth false
      end
    end
  end
end
