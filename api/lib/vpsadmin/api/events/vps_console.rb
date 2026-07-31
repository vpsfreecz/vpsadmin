module VpsAdmin::API::Events::VpsConsole
  CLOSE_REASONS = %w[
    client_closed
    console_ended
    node_restart
    node_shutdown
    router_timeout
    session_timeout
  ].freeze
end

VpsAdmin::API::Events.define do
  {
    'vps.console_opened' => 'VPS console opened',
    'vps.console_closed' => 'VPS console closed'
  }.each do |event_name, label|
    action = event_name.delete_prefix('vps.console_')

    event event_name,
          label:,
          category: 'vps',
          severity: :info,
          audience: :account,
          roles: %i[account admin],
          default_routed: false,
          examples: {
            subject: "VPS #123 console #{action}",
            summary: "Remote console client #{action} on node1.example.org"
          } do
      fields(
        vps_id: { description: 'ID of the affected VPS', type: :integer },
        vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
        node_id: { description: 'ID of the node hosting the VPS console', type: :integer },
        node_name: {
          description: 'Domain name of the node hosting the VPS console',
          type: :string,
          example: 'node1.example.org'
        },
        console_client_id: {
          description: 'Ephemeral identifier correlating console open and close events',
          type: :string,
          example: '0123456789abcdef0123456789abcdef'
        },
        producer_event_id: {
          description: 'Stable node-assigned identifier used to deduplicate console event delivery',
          type: :string,
          example: '00000000-0000-4000-8000-000000000001'
        },
        actor_user_id: {
          description: 'ID of the user whose console token authenticated the client',
          type: :integer
        },
        vps_console_id: {
          description: 'ID of the console authorization record used by the client',
          type: :integer
        }
      )

      if event_name == 'vps.console_closed'
        field(
          :close_reason,
          'Reason why the console client was closed',
          type: :string,
          example: 'session_timeout',
          choices: VpsAdmin::API::Events::VpsConsole::CLOSE_REASONS
        )
      end
    end
  end
end
