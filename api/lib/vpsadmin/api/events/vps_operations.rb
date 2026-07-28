# frozen_string_literal: true

require 'time'

module VpsAdmin::API::Events::VpsOperations
  SUCCESS_EVENT_TYPE = 'vps.operation_succeeded'
  FAILURE_EVENT_TYPE = 'vps.operation_failed'

  CHAIN_OPERATIONS = {
    'TransactionChains::Vps::AddIp' => %w[add_ip add_ip],
    'TransactionChains::Vps::ApplyConfig' => %w[apply_config apply_config],
    'TransactionChains::Vps::Autostart' => %w[autostart autostart],
    'TransactionChains::Vps::Block' => %w[block block],
    'TransactionChains::Vps::Boot' => %w[boot boot],
    'TransactionChains::Vps::Clone::OsToOs' => %w[os_to_os clone],
    'TransactionChains::Vps::Clone::VzToOs' => %w[vz_to_os clone],
    'TransactionChains::Vps::Clone::VzToVz' => %w[vz_to_vz clone],
    'TransactionChains::Vps::Create' => %w[create create],
    'TransactionChains::Vps::CreateVeth' => %w[create_veth create_veth],
    'TransactionChains::Vps::DelIp' => %w[del_ip delete_ip],
    'TransactionChains::Vps::DeployPublicKey' => %w[deploy_public_key deploy_public_key],
    'TransactionChains::Vps::DeployUserData' => %w[deploy_user_data deploy_user_data],
    'TransactionChains::Vps::Destroy' => %w[destroy destroy],
    'TransactionChains::Vps::DestroyMount' => %w[destroy_mount destroy_mount],
    'TransactionChains::Vps::EnableNetwork' => %w[enable_network enable_network],
    'TransactionChains::Vps::ExpandDataset' => %w[expand_dataset expand_dataset],
    'TransactionChains::Vps::ExpandDatasetAgain' => %w[expand_dataset_again expand_dataset_again],
    'TransactionChains::Vps::Features' => %w[features set_features],
    'TransactionChains::Vps::Migrate::OsToOs' => %w[os_to_os migrate],
    'TransactionChains::Vps::Migrate::OsToVz' => %w[os_to_vz migrate],
    'TransactionChains::Vps::Migrate::VzToOs' => %w[vz_to_os migrate],
    'TransactionChains::Vps::Migrate::VzToVz' => %w[vz_to_vz migrate],
    'TransactionChains::Vps::Mount' => %w[mount mount],
    'TransactionChains::Vps::MountDataset' => %w[mount_dataset mount_dataset],
    'TransactionChains::Vps::MountSnapshot' => %w[mount_snapshot mount_snapshot],
    'TransactionChains::Vps::Mounts' => %w[mounts regenerate_mounts],
    'TransactionChains::Vps::OomPrevention' => %w[oom_prevention oom_prevention],
    'TransactionChains::Vps::Passwd' => %w[passwd set_password],
    'TransactionChains::Vps::Reinstall' => %w[reinstall reinstall],
    'TransactionChains::Vps::RemoveVeth' => %w[remove_veth remove_veth],
    'TransactionChains::Vps::Replace::Os' => %w[os replace],
    'TransactionChains::Vps::Restart' => %w[restart restart],
    'TransactionChains::Vps::Restore' => %w[restore restore],
    'TransactionChains::Vps::Revive' => %w[revive revive],
    'TransactionChains::Vps::SetResources' => %w[set_resources set_resources],
    'TransactionChains::Vps::SetUserNamespaceMap' => %w[set_user_namespace_map set_user_namespace_map],
    'TransactionChains::Vps::ShaperChange' => %w[shaper_change shaper_change],
    'TransactionChains::Vps::ShaperSet' => %w[shaper_set shaper_set],
    'TransactionChains::Vps::ShaperUnset' => %w[shaper_unset shaper_unset],
    'TransactionChains::Vps::ShrinkDataset' => %w[shrink_dataset shrink_dataset],
    'TransactionChains::Vps::SoftDelete' => %w[soft_delete soft_delete],
    'TransactionChains::Vps::Start' => %w[start start],
    'TransactionChains::Vps::Stop' => %w[stop stop],
    'TransactionChains::Vps::StopOverQuota' => %w[stop_over_quota stop_over_quota],
    'TransactionChains::Vps::Swap' => %w[swap swap],
    'TransactionChains::Vps::Umount' => %w[umount umount],
    'TransactionChains::Vps::UmountDataset' => %w[umount_dataset umount_dataset],
    'TransactionChains::Vps::UmountSnapshot' => %w[umount_snapshot umount_snapshot],
    'TransactionChains::Vps::Unblock' => %w[unblock unblock],
    'TransactionChains::Vps::Update' => %w[update update],
    'TransactionChains::Vps::UpdateMount' => %w[update_mount update_mount],
    'TransactionChains::Lifetimes::Wrapper' => %w[wrapper lifecycle_change]
  }.freeze

  TERMINAL_EVENT_TYPES = {
    'done' => SUCCESS_EVENT_TYPE,
    'failed' => FAILURE_EVENT_TYPE,
    'fatal' => FAILURE_EVENT_TYPE
  }.freeze

  module_function

  def emit_terminal!(chain, state:, changed_at: nil, node: nil,
                     producer_event_id: nil)
    event_type = TERMINAL_EVENT_TYPES[state.to_s]
    operation = operation_for(chain)
    return if event_type.nil? || operation.nil?

    vps_ids = vps_concern_ids(chain)
    return if vps_ids.empty?

    primary_vps_id = vps_ids.last
    vps = ::Vps.find_by(id: primary_vps_id)
    owner = vps&.user ||
            VpsAdmin::API::Events.transaction_chain_target_owner(chain) ||
            accepted_owner(chain) ||
            chain.user
    successful = event_type == SUCCESS_EVENT_TYPE

    VpsAdmin::API::Events.emit!(
      event_type,
      user: owner,
      vps:,
      source_class: ::TransactionChain.name,
      source_id: chain.id,
      subject: subject(operation, primary_vps_id, successful),
      summary: summary(operation, chain, state),
      severity: severity(state),
      payload: {
        operation:,
        chain_id: chain.id,
        chain_name: chain.name,
        chain_type: chain.type,
        state: state.to_s,
        successful:,
        vps_id: primary_vps_id,
        vps_ids:,
        vps_hostname: vps&.hostname,
        actor_user_id: chain.user_id,
        user_session_id: chain.user_session_id,
        node_id: node&.id,
        node_name: node&.domain_name,
        producer_event_id:,
        changed_at: (changed_at || Time.now).iso8601
      }.compact,
      occurred_at: changed_at
    )
  end

  def operation_for(chain)
    expected_name, operation = CHAIN_OPERATIONS[chain.type.to_s]
    return if expected_name.nil? || chain.name.to_s != expected_name

    operation
  end

  def vps_concern_ids(chain)
    chain.transaction_chain_concerns.sort_by(&:id).filter_map do |concern|
      concern.row_id if concern.class_name == ::Vps.name
    end.uniq
  end

  def accepted_owner(chain)
    ::Event
      .where(
        event_type: 'transaction_chain.state_changed',
        source_class: ::TransactionChain.name,
        source_id: chain.id
      )
      .order(:id)
      .detect { |event| event.parameters['state'] == 'queued' }
      &.user
  end

  def subject(operation, vps_id, successful)
    outcome = successful ? 'succeeded' : 'failed'
    "VPS ##{vps_id} #{operation.humanize.downcase} #{outcome}"
  end

  def summary(operation, chain, state)
    "VPS #{operation.humanize.downcase} transaction chain ##{chain.id} finished as #{state}"
  end

  def severity(state)
    case state.to_s
    when 'done'
      :info
    when 'fatal'
      :critical
    else
      :error
    end
  end
end

VpsAdmin::API::Events.define do
  {
    VpsAdmin::API::Events::VpsOperations::SUCCESS_EVENT_TYPE => [
      'VPS operation succeeded',
      :info
    ],
    VpsAdmin::API::Events::VpsOperations::FAILURE_EVENT_TYPE => [
      'VPS operation failed',
      :error
    ]
  }.each do |event_name, (label, severity)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          roles: %i[account admin],
          default_routed: false do
      fields(
        operation: { description: 'VPS operation represented by the transaction chain', type: :string },
        chain_id: { description: 'ID of the transaction chain', type: :integer },
        chain_name: { description: 'Persisted transaction chain name', type: :string },
        chain_type: { description: 'Persisted transaction chain type', type: :string },
        state: { description: 'Terminal transaction chain state', type: :string },
        successful: { description: 'Whether the VPS operation succeeded', type: :boolean },
        vps_id: { description: 'ID of the primary VPS affected by the operation', type: :integer },
        vps_ids: { description: 'IDs of all VPSes affected by the operation', type: :integer_list },
        vps_hostname: { description: 'Current hostname of the primary VPS, when available', type: :string },
        actor_user_id: { description: 'ID of the user who initiated the transaction chain', type: :integer },
        user_session_id: { description: 'ID of the session that initiated the transaction chain', type: :integer },
        node_id: { description: 'ID of the node reporting the terminal state', type: :integer },
        node_name: { description: 'Name of the node reporting the terminal state', type: :string },
        producer_event_id: {
          description: 'Stable node-assigned identifier for this state transition',
          type: :string
        },
        changed_at: { description: 'Time when the terminal state was reported', type: :datetime }
      )
    end
  end
end
