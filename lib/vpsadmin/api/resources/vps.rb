class VpsAdmin::API::Resources::VPS < VpsAdmin::API::Resource
  version 1
  model ::Vps
  desc 'Manage VPS'

  params(:common) do
    foreign_key :user_id, label: 'User', desc: 'VPS owner', db_name: :m_id
    string :hostname, desc: 'VPS hostname', db_name: :vps_hostname
    foreign_key :template_id, label: 'Template', desc: 'id of OS template', db_name: :vps_template
    string :info, label: 'Info', desc: 'VPS description', db_name: :vps_info
    foreign_key :dns_resolver_id, label: 'DNS resolver', desc: 'DNS resolver the VPS will use', db_name: :vps_nameserver
    integer :node_id, label: 'Node', desc: 'Node VPS will run on', db_name: :vps_server
    bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?', db_name: :vps_onboot
    bool :onstartall, label: 'On start all', desc: 'Start VPS on start all action?', db_name: :vps_onstartall
    bool :backup_enabled, label: 'Enable backups', desc: 'Toggle VPS backups', db_name: :vps_backup_enabled
    string :config, label: 'Config', desc: 'Custom configuration options', db_name: :vps_config
  end

  class Index < VpsAdmin::API::Actions::Default::Index
    desc 'List VPS'

    output(:vpses) do
      list_of_objects
      use :common
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(vps_id hostname template_id dns_resolver_id node_id backup_enabled)
      allow
    end

    example do
      request({})
      response({vpses: [
        {
            vps_id: 150,
            user_id: 1,
            hostname: 'thehostname',
            template_id: 1,
            info: 'My very important VPS',
            dns_resolver_id: 1,
            node_id: 1,
            onboot: true,
            onstartall: true,
            backup_enabled: true,
            config: '',
        }
      ]})
    end

    def exec
      ret = []

      Vps.where(with_restricted).each do |vps|
        ret << {
          vps_id: vps.id,
          hostname: vps.hostname,
          template_id: vps.os_template.id,
          info: vps.vps_info,
          dns_resolver_id: 1,
          node_id: vps.node.id,
          onboot: vps.vps_onboot,
          onstartall: vps.vps_onstartall,
          backup_enabled: vps.vps_backup_enabled,
          config: vps.vps_config,
        }
      end

      ret
    end
  end

  class Create < VpsAdmin::API::Actions::Default::Create
    desc 'Create VPS'

    input(:vps) do
      use :common
    end

    output do
      object
      integer :vps_id, label: 'VPS id', desc: 'ID of created VPS'
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(hostname template_id dns_resolver_id)
      allow
    end

    example do
      request({
        vps: {
          user_id: 1,
          hostname: 'my-vps',
          template_id: 1,
          info: '',
          dns_resolver_id: 1,
          node_id: 1,
          onboot: true,
          onstartall: true,
          backup_enabled: true,
          config: ''
        }
      })
      response({
        vps: {
            vps_id: 150
        }
      })
      comment <<END
Create VPS owned by user with ID 1, template ID 1 and DNS resolver ID 1. VPS
will be created on node ID 1. Action returns ID of newly created VPS.
END
    end

    def exec
      vps_params = params[:vps]

      if current_user.role != :admin
        vps_params[:user_id] = current_user.m_id
      end

      vps = Vps.new(to_db_names(vps_params))

      if vps.save
        Transactions::Vps::New.fire(self)
        ok({vps_id: vps.id})

      else
        error('save failed', to_param_names(vps.errors.to_hash, :input))
      end
    end
  end

  class Show < VpsAdmin::API::Actions::Default::Show
    desc 'Show VPS properties'

    output do
      object
      use :common
    end

    # example do
    #   request({})
    #   response({})
    #   comment ''
    # end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = Vps.find_by!(with_restricted(vps_id: params[:vps_id]))

      {
          vps_id: vps.vps_id,
          hostname: vps.hostname,
          distribution: 15615
      }
    end
  end

  class Update < VpsAdmin::API::Actions::Default::Update
    input do
      use :common
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
    end
  end

  class Delete < VpsAdmin::API::Actions::Default::Delete

  end

  class Start < VpsAdmin::API::Action
    desc 'Start VPS'
    route ':%{resource}_id/start'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      ::Vps.find(params[:vps_id]).start
      ok
    end
  end

  class Restart < VpsAdmin::API::Action
    desc 'Restart VPS'
    route ':%{resource}_id/restart'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      ::Vps.find(params[:vps_id]).restart
      ok
    end
  end

  class Stop < VpsAdmin::API::Action
    desc 'Stop VPS'
    route ':%{resource}_id/stop'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      ::Vps.find(params[:vps_id]).stop
      ok
    end
  end

  class IpAddress < VpsAdmin::API::Resource
    version 1
    model IpAddress
    route ':vps_id/ip_addresses'
    desc 'Manage VPS IP addresses'

    class Index < VpsAdmin::API::Actions::Default::Index

    end

    class Show < VpsAdmin::API::Actions::Default::Show

    end
  end
end
