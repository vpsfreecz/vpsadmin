module VpsAdmin
  module API
    module Resources
      class VPS < API::Resource
        version 1
        model ::Vps
        desc 'Manage VPS'

        class Index < API::Actions::Default::Index
          desc 'List VPS'

          output do
            list_of(:vpses, {
              vps_id: Integer,
              hostname: String,
            })

            integer :vps_id, label: 'VPS id'
            string :hostname, label: 'Hostname'
          end

          authorize do |u|
            allow if u.role == :admin
            restrict m_id: u.m_id
            allow
          end

          def exec
            ret = []

            Vps.where(with_restricted).each do |vps|
              ret << {
                vps_id: vps.id,
                hostname: vps.hostname,
              }
            end

            ret
          end
        end

        class Create < API::Actions::Default::Create
          desc 'Create VPS'

          input do
            id :user_id, label: 'User', desc: 'VPS owner'
            string :hostname, desc: 'VPS hostname'
            foreign_key :template_id, label: 'Template', desc: 'id of OS template'
            string :info, label: 'Info', desc: 'VPS description'
            foreign_key :dns_resolver_id, label: 'DNS resolver', desc: 'DNS resolver the VPS will use'
            string :node_id, label: 'Node', desc: 'Node VPS will run on'
            bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?'
            bool :onstartall, label: 'On start all', desc: 'Start VPS on start all action?'
            bool :backup_enabled, label: 'Enable backups', desc: 'Toggle VPS backups'
            string :config, label: 'Config', desc: 'Custom configuration options'
          end

          output do
            object(:vps, {
              vps_id: Integer
            })

            integer :vps_id, label: 'VPS id', desc: 'ID of created VPS'
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
          end

          def exec
            puts 'Did magic'
          end
        end

        class Show < API::Actions::Default::Show
          desc 'Show VPS properties'

          output do
            object(:vps, {
              vps_id: Integer,
              hostname: String,
              distribution: Integer,
            })
          end

          # example do
          #   request({})
          #   response({})
          #   comment ''
          # end

          authorize do |u|
            restrict m_id: u.m_id
            allow
          end

          def exec
            vps = Vps.find_by!(with_restricted(vps_id: @params[:vps_id]))

            {
                vps_id: vps.vps_id,
                hostname: vps.hostname,
                distribution: 15615
            }
          end
        end

        class Update < API::Actions::Default::Update
          input do
            param :id, desc: 'VPS id'
          end

          authorize do |u|
            restrict m_id: u.m_id
            whitelist
          end
        end

        class Delete < API::Actions::Default::Delete

        end

        class IpAddress < API::Resource
          version 1
          model IpAddress
          route ':vps_id/ip_addresses'
          desc 'Manage VPS IP addresses'

          class Index < API::Actions::Default::Index

          end

          class Show < API::Actions::Default::Show

          end
        end
      end
    end
  end
end
