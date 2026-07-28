VpsAdmin::API::Events.define do
  {
    'vps.console_opened' => 'VPS console opened',
    'vps.console_closed' => 'VPS console closed'
  }.each do |event_name, label|
    event event_name,
          label:,
          category: 'vps',
          severity: :info,
          roles: %i[account admin],
          default_routed: false do
      fields(
        vps_id: { description: 'ID of the affected VPS', type: :integer },
        vps_hostname: { description: 'Hostname of the affected VPS', type: :string },
        node_id: { description: 'ID of the node hosting the VPS console', type: :integer },
        node_name: { description: 'Domain name of the node hosting the VPS console', type: :string },
        console_client_id: {
          description: 'Ephemeral identifier correlating console open and close events',
          type: :string
        },
        producer_event_id: {
          description: 'Stable node-assigned identifier used to deduplicate console event delivery',
          type: :string
        },
        actor_user_id: {
          description: 'ID of the user whose console token authenticated the client',
          type: :integer
        },
        vps_console_id: {
          description: 'ID of the console authorization record used by the client',
          type: :integer
        },
        close_reason: { description: 'Reason why the console client was closed', type: :string }
      )
    end
  end
end
