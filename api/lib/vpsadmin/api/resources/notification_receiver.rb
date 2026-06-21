module VpsAdmin::API::Resources
  class NotificationReceiver < HaveAPI::Resource
    desc 'Manage notification receivers'
    model ::NotificationReceiver

    params(:common) do
      resource User, value_label: :login
      string :label
      text :description, nullable: true
      bool :enabled
      bool :mute
      string :display_action_summary
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List notification receivers'

      input do
        use :common, include: %i[user enabled mute]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        q = self.class.model.where(with_restricted)

        %i[user enabled mute].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query.order(:label, :id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show notification receiver'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create notification receiver'

      input do
        use :common, include: %i[user label description enabled mute]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        owner = input[:user] || current_user

        if current_user.role != :admin && owner != current_user
          error!('access denied')
        end

        self.class.model.create!(
          user: owner,
          label: input[:label],
          description: input[:description],
          enabled: input.has_key?(:enabled) ? input[:enabled] : true,
          mute: input.has_key?(:mute) ? input[:mute] : false
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update notification receiver'

      input do
        use :common, include: %i[label description enabled mute]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        receiver = self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
        receiver.update!(input)
        receiver
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete notification receiver'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        receiver = self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
        receiver.destroy!
        ok!
      end
    end

    class Action < HaveAPI::Resource
      model ::NotificationReceiverAction
      route '{notification_receiver_id}/action'
      desc 'Manage notification receiver actions'

      params(:common) do
        string :action,
               choices: { values: ::NotificationReceiverAction.action_labels },
               load_validators: false
        string :label, nullable: true
        string :target_kind,
               choices: { values: ::NotificationReceiverAction.target_kind_labels },
               load_validators: false
        text :target_value, nullable: true
        bool :enabled
        datetime :verified_at, nullable: true
        bool :verified
        string :verification_token, nullable: true
        text :config_json, label: 'Configuration'
        bool :secret_present
        text :last_error, nullable: true
        string :display_target
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List notification receiver actions'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(:notification_receiver).where(
            with_restricted(notification_receiver_id: path_params['notification_receiver_id'])
          )
        end

        def count
          query.count
        end

        def exec
          with_pagination(query.order(:id))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show notification receiver action'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['action_id']
            )
          )
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create notification receiver action'

        input do
          use :common, include: %i[
            action
            label
            target_kind
            target_value
            enabled
          ]
          text :secret, nullable: true
          %i[action].each { |v| patch v, required: true }
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user_id: u.id
          allow
        end

        def exec
          receiver = ::NotificationReceiver.find_by!(
            with_restricted(id: path_params['notification_receiver_id'])
          )

          action = receiver.notification_receiver_actions.create!(
            action: input[:action],
            label: input[:label],
            target_kind: input[:target_kind] || default_target_kind,
            target_value: input[:target_value],
            enabled: input.has_key?(:enabled) ? input[:enabled] : true,
            secret: input[:secret]
          )

          action.generate_verification_token! if action.telegram_action?
          action
        rescue ActiveRecord::RecordInvalid => e
          error!('create failed', e.record.errors.to_hash)
        end

        def default_target_kind
          input[:action] == 'email' ? 'default_recipient' : 'custom'
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update notification receiver action'

        input do
          use :common, include: %i[
            action
            label
            target_kind
            target_value
            enabled
          ]
          text :secret, nullable: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          action = self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['action_id']
            )
          )

          attrs = {}
          %i[action label target_kind target_value enabled].each do |v|
            attrs[v] = input[v] if input.has_key?(v)
          end
          attrs[:secret] = input[:secret] if input.has_key?(:secret) && !input[:secret].nil?

          action.update!(attrs)
          action
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete notification receiver action'

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          action = self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['action_id']
            )
          )
          action.destroy!
          ok!
        end
      end

      class CreatePairingToken < HaveAPI::Action
        desc 'Create Telegram pairing token'
        route '{action_id}/create_pairing_token'
        http_method :post

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          action = ::NotificationReceiverAction.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['action_id']
            )
          )
          error!('receiver action is not Telegram') unless action.telegram_action?
          error!('Telegram delivery is not configured') unless action.action_available?

          action.generate_verification_token!
          action
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
        end
      end
    end
  end
end
