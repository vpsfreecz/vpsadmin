module VpsAdmin::API::Resources
  class SecurityAdvisoryUpdate < HaveAPI::Resource
    desc 'Browse security advisory updates'
    model ::SecurityAdvisoryUpdate

    PUBLISHED_AT_DESCRIPTION =
      'Date and time shown as the advisory publication time.'.freeze
    SEND_MAIL_DESCRIPTION =
      'When enabled, affected users are emailed after the action completes.'.freeze
    TEXT_DESCRIPTIONS = {
      summary: 'One-sentence public summary of this update, shown in ' \
               'update lists and emails.',
      message: 'Optional user-facing message with more details about this update.'
    }.freeze

    params(:texts) do
      ::Language.all.each do |lang|
        string :"#{lang.code}_summary",
               label: "#{lang.label} summary",
               desc: TEXT_DESCRIPTIONS[:summary]
        text :"#{lang.code}_message",
             label: "#{lang.label} message",
             desc: TEXT_DESCRIPTIONS[:message],
             nullable: true
      end
    end

    params(:state_change) do
      string :state,
             choices: ::SecurityAdvisory.states.keys.map(&:to_s),
             desc: 'Optional advisory state change to apply with this update.',
             nullable: true
    end

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::SecurityAdvisory, value_label: :id
      use :state_change
      use :texts
      resource VpsAdmin::API::Resources::User, name: :reported_by, value_label: :login, nullable: true
      string :reporter_name
      string :name, nullable: true
      datetime :created_at
      datetime :updated_at
    end

    module Helpers
      def extract_translations
        tr = {}

        ::Language.all.each do |lang|
          %i[summary message].each do |param|
            name = :"#{lang.code}_#{param}"

            if input.has_key?(name)
              tr[lang] ||= {}
              tr[lang][param] = input.delete(name)
            end
          end
        end

        tr
      end
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List security advisory updates'
      auth false

      input do
        resource VpsAdmin::API::Resources::SecurityAdvisory, label: 'Security advisory'
        datetime :since, label: 'Since'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i[reported_by]
        allow
      end

      def query
        q = ::SecurityAdvisoryUpdate
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))

        q = q.where(security_advisory: input[:security_advisory]) if input[:security_advisory]
        q = q.where('security_advisory_updates.created_at > ?', input[:since]) if input[:since]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('security_advisory_updates.created_at')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show security advisory update'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow if u && u.role == :admin
        output blacklist: %i[reported_by]
        allow
      end

      def prepare
        @update = with_includes(
          ::SecurityAdvisoryUpdate
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))
        ).find(path_params['security_advisory_update_id'])
      end

      def exec
        @update
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include Helpers

      desc 'Create security advisory update'
      blocking true

      input do
        resource VpsAdmin::API::Resources::SecurityAdvisory,
                 label: 'Security advisory',
                 desc: 'Advisory to which this update belongs.'
        use :state_change
        use :texts
        datetime :published_at,
                 label: 'Published at',
                 desc: PUBLISHED_AT_DESCRIPTION,
                 nullable: true
        bool :send_mail,
             label: 'Send mail',
             desc: SEND_MAIL_DESCRIPTION,
             default: false,
             fill: true
        patch :security_advisory, required: true
        ::Language.all.each do |lang|
          patch :"#{lang.code}_summary", required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        advisory = input.delete(:security_advisory)
        has_published_at = input.has_key?(:published_at)
        published_at = input.delete(:published_at)
        send_mail = input.delete(:send_mail)
        tr = extract_translations
        @advisory = advisory
        advisory.create_update!(
          to_db_names(input),
          tr,
          advisory_attrs: has_published_at ? { published_at: } : {},
          send_mail:
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @advisory&.last_chain&.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include Helpers

      desc 'Update security advisory update text'

      input do
        use :texts
        ::Language.all.each do |lang|
          patch :"#{lang.code}_summary", required: true
        end
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        update = ::SecurityAdvisoryUpdate.find(path_params['security_advisory_update_id'])
        update.update_translations!(extract_translations)
        update
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete security advisory update'

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @update = ::SecurityAdvisoryUpdate.find(path_params['security_advisory_update_id'])
      end

      def exec
        @update.destroy!
        ok!
      end
    end
  end
end
