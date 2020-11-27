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
        bool :activate, label: 'Activate account', default: true, fill: true
        resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :domain_name,
            desc: 'Create the new VPS on this node'
        bool :create_vps, label: 'Create VPS', default: true, fill: true
      end

      params(:token) do
        string :token, label: 'Access token'
      end

      params(:properties) do
        bool :ip_checked
        string :ip_request_id
        bool :ip_success
        string :ip_message
        string :ip_errors
        bool :ip_proxy
        bool :ip_crawler
        bool :ip_recent_abuse
        bool :ip_vpn
        bool :ip_tor
        integer :ip_fraud_score

        bool :mail_checked
        string :mail_request_id
        bool :mail_success
        string :mail_message
        string :mail_errors
        bool :mail_valid
        bool :mail_disposable
        bool :mail_timed_out
        string :mail_deliverability
        bool :mail_catch_all
        bool :mail_leaked
        bool :mail_suspect
        integer :mail_smtp_score
        integer :mail_overall_score
        integer :mail_fraud_score
        bool :mail_dns_valid
        bool :mail_honeypot
        string :mail_spam_trap_score
        bool :mail_recent_abuse
        bool :mail_frequent_complainer
      end

      include VpsAdmin::API::Plugins::Requests::BaseResource

      class Create
        auth false
      end

      class Preview < HaveAPI::Action
        auth false
        http_method :get
        route '{%{resource}_id}/{token}'

        output do
          use :common, include: %i(id admin_response)
          use :request
        end

        authorize do |u|
          allow
        end

        def exec
          ::RegistrationRequest.find_by!(with_restricted(
            id: params[:registration_id],
            access_token: params[:token],
            state: ::RegistrationRequest.states[:pending_correction],
          ))
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        auth false
        route '{%{resource}_id}/{token}'

        input do
          use :request
        end

        output do
          use :common, include: %i(id)
          use :request
        end

        authorize do |u|
          allow
        end

        def exec
          req = ::RegistrationRequest.find_by!(with_restricted(
            id: params[:registration_id],
            access_token: params[:token],
            state: ::RegistrationRequest.states[:pending_correction],
          ))
          req.resubmit!(input)
          req

        rescue ActiveRecord::RecordInvalid => e
          error('update failed', e.record.errors.to_hash)
        end
      end
    end
  end
end
