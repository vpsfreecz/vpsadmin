module VpsAdmin::API::Resources
  class UserRequest
    class Registration < HaveAPI::Resource
      desc 'Request account registration'
      model ::RegistrationRequest

      params(:request) do
        string :login, required: true
        string :full_name, required: true
        string :org_name
        string :org_id
        string :email, required: true
        text :address, required: true
        integer :year_of_birth, required: true
        string :how
        string :note
        resource VpsAdmin::API::Resources::OsTemplate, required: true
        resource VpsAdmin::API::Resources::Location, required: true
        string :currency, required: true
        resource VpsAdmin::API::Resources::Language, required: true
      end
    end

    include VpsAdmin::API::Plugins::Requests::BaseResource
  end
end
