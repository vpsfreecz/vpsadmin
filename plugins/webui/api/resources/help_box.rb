module VpsAdmin::API::Resources
  class HelpBox < HaveAPI::Resource
    desc 'Browse and manage help boxes'
    model ::HelpBox

    params(:filters) do
      string :page
      string :action
      resource VpsAdmin::API::Resources::Language
    end

    params(:editable) do
      use :filters
      text :content
      integer :order
    end

    params(:all) do
      id :id
      use :editable
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List help boxes'
      auth false

      input do
        use :filters
        bool :view, default: false, fill: true,
                    desc: 'When enabled, list help boxes for the current user, including page/action filters'
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        q = ::HelpBox.all

        if input[:view]
          if input.has_key?(:page) || input.has_key?(:action)
            q = q.where(
              "(page = ? AND (action = ? OR action = '*'))
              OR
              (page = '*' AND (action = ? OR action = '*'))",
              input[:page], input[:action], input[:action]
            )
          end

          q = if input.has_key?(:language)
                q.where(language: input[:language])

              else
                q.where(
                  'language_id IS NULL OR language_id = ?',
                  current_user ? current_user.language_id : ::Language.take!.id
                )
              end
        else
          %i[page action].each do |f|
            q = q.where(f => input[f]) if input[f]
          end

          q = q.where(language: input[:language]) if input.has_key?(:language)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order(:order, :page, :action)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show helpbox'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @box = ::HelpBox.find(params[:help_box_id])
      end

      def exec
        @box
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a help box'

      input do
        use :editable
        patch :content, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::HelpBox.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('Create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update help box'

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        box = ::HelpBox.find(params[:help_box_id])
        box.update!(input)
        box
      rescue ActiveRecord::RecordInvalid => e
        error!('Update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete help box'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        box = ::HelpBox.find(params[:help_box_id])
        box.destroy!
        ok!
      end
    end
  end
end
