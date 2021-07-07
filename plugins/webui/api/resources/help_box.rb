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
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow
      end

      def query
        q = ::HelpBox.all

        if input.has_key?(:page) || input.has_key?(:action)
          q = q.where(
            "(page = ? AND (action = ? OR action = '*'))
            OR
            (page = '*' AND (action = ? OR action = '*'))",
            input[:page], input[:action], input[:action]
          )
        end

        if input.has_key?(:language)
          q = q.where(language: input[:language])

        else
          q = q.where(
            'language_id IS NULL OR language_id = ?',
            current_user ? current_user.language_id : ::Language.take!.id
          )
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
          .limit(input[:limit])
          .offset(input[:offset])
          .order(:order, :page, :action)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show helpbox'
      auth false

      output do
        use :all
      end

      authorize do |u|
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
        error('Create failed', e.record.errors.to_hash)
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
        error('Update failed', e.record.errors.to_hash)
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
        ok
      end
    end
  end
end
