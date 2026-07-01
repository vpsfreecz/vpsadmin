class VpsAdmin::API::Resources::TransactionChain < HaveAPI::Resource
  model ::TransactionChain
  desc 'Access transaction chains'

  params(:all) do
    id :id, label: 'Chain ID'
    string :name, label: 'Name', desc: 'For internal use only'
    string :label, label: 'Label', desc: 'Human-friendly name'
    string :state, label: 'State', choices: ::TransactionChain.states.keys
    integer :size, label: 'Size', desc: 'Number of transactions in the chain'
    integer :progress, label: 'Progress', desc: 'How many transactions are finished'
    resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
    resource VpsAdmin::API::Resources::UserSession, label: 'User session'
    datetime :created_at, label: 'Creation date'
    custom :concerns, db_name: :format_concerns
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List transaction chains'

    input do
      string :name, label: 'Name', desc: 'For internal use only'
      string :state, label: 'State', choices: ::TransactionChain.states.keys
      resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
      resource VpsAdmin::API::Resources::UserSession, label: 'User session'
      string :class_name, label: 'Class name', desc: 'Search by concerned class name'
      integer :row_id, label: 'Row id', desc: 'Search by concerned row id'

      patch :limit, default: 25, fill: true
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      input blacklist: %i[user]
      output blacklist: %i[user]
      allow
    end

    def query
      q = ::TransactionChain.where(with_restricted).group('transaction_chains.id')

      q = q.where(name: input[:name]) if input[:name]
      q = q.where(state: ::TransactionChain.states[input[:state]]) if input[:state]
      q = q.where(user: input[:user]) if input[:user]
      q = q.where(user_session: input[:user_session]) if input[:user_session]
      if input[:class_name]
        q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: { class_name: input[:class_name] }
        )
      end
      if input[:row_id]
        q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: { row_id: input[:row_id] }
        )
      end

      q
    end

    def count
      result = query.count
      result.is_a?(Hash) ? result.size : result
    end

    def exec
      with_desc_pagination(with_includes(query))
        .includes(:transaction_chain_concerns)
        .order('transaction_chains.created_at DESC, transaction_chains.id DESC')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show transaction chain'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      output blacklist: %i[user]
      allow
    end

    def prepare
      @chain = ::TransactionChain.find_by(with_restricted(id: path_params['transaction_chain_id']))
      error!('transaction chain not found', {}, http_status: 404) unless @chain
    end

    def exec
      @chain
    end
  end

  class NotifyWhenDone < HaveAPI::Action
    desc 'Create a single-use route notifying when this transaction chain finishes'
    route '{%{resource}_id}/notify_when_done'
    http_method :post

    input do
      integer :notification_receiver_id, nullable: true
      datetime :expires_at, nullable: true
    end

    output namespace: :event_route do
      id :id
      integer :parent_id, nullable: true
      integer :notification_receiver_id, nullable: true
      string :label, nullable: true
      integer :position
      bool :enabled
      string :event_type,
             choices: { values: VpsAdmin::API::Events.type_labels },
             load_validators: false,
             nullable: true
      string :event_type_pattern, label: 'Event type pattern', nullable: true
      bool :continue
      integer :hit_count, label: 'Hits'
      bool :single_use
      datetime :spent_at, nullable: true
      datetime :expires_at, nullable: true
      string :matcher_summary
      string :display_label
      datetime :created_at
      datetime :updated_at
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      allow
    end

    def prepare
      @chain = ::TransactionChain.find_by(with_restricted(id: path_params['transaction_chain_id']))
      error!('transaction chain not found', {}, http_status: 404) unless @chain
    end

    def exec
      route = nil
      ::EventRoute.transaction do
        @chain.lock!
        receiver = notification_receiver
        state_change_threshold = Time.now.to_f

        if @chain.user.event_routes.active.count >= ::EventRoute::MAX_ROUTES
          error!('route limit reached, refusing to add another one')
        end

        route = @chain.user.event_routes.create!(
          notification_receiver: receiver,
          label: "Notify when transaction chain ##{@chain.id} finishes",
          position: ::EventRoute.prepend_position_for(@chain.user),
          event_type: 'transaction_chain.state_changed',
          single_use: true,
          expires_at: input[:expires_at]
        )

        route.event_route_matchers.create!(
          field: 'chain_id',
          operator: '==',
          value: @chain.id.to_s
        )
        route.event_route_matchers.create!(
          field: 'terminal',
          operator: '==',
          value: 'true'
        )
        route.event_route_matchers.create!(
          field: 'changed_at_timestamp',
          operator: '>=',
          value: format('%.6f', state_change_threshold)
        )

        emit_current_state!(route) if terminal_state?(@chain.state)
      end

      route.reload
    rescue ActiveRecord::RecordInvalid => e
      error!('create failed', e.record.errors.to_hash)
    end

    protected

    def notification_receiver
      if input[:notification_receiver_id].present?
        receiver = ::NotificationReceiver.find_by(
          id: input[:notification_receiver_id],
          user_id: @chain.user_id
        )
        error!('notification receiver not found') unless receiver
        return receiver
      end

      ::NotificationReceiver.ensure_defaults_for!(@chain.user)
      ::NotificationReceiver.default_email_receiver_for(@chain.user)
    end

    def terminal_state?(state)
      VpsAdmin::API::Events::TRANSACTION_CHAIN_TERMINAL_STATES.include?(state.to_s)
    end

    def emit_current_state!(route)
      VpsAdmin::API::Events.emit_transaction_chain_state!(
        @chain,
        previous_state: nil,
        state: @chain.state
      )
      route.reload
    end
  end
end
