module VpsAdmin::API::Resources
  class UserRequest
    class Change < HaveAPI::Resource
      desc 'Request change of personal information'
      model ::ChangeRequest

      params(:request) do
        string :change_reason, label: 'Change reason', required: true,
            desc: 'Why do you wish to make the change?'
        string :full_name, label: 'Full name'
        string :email, label: 'E-mail'
        string :address, label: 'Address'
      end

      include VpsAdmin::API::Plugins::Requests::BaseResource
    end
  end
end
