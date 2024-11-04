class VpsAdmin::API::Resources::UserNamespaceMap < HaveAPI::Resource
  model ::UserNamespaceMap
  desc 'Browse user namespace maps'

  params(:common) do
    resource VpsAdmin::API::Resources::UserNamespace, value_label: :id
    string :label, label: 'Label'
  end

  params(:all) do
    id :id, label: 'Map ID'
    use :common
  end

  params(:filters) do
    resource VpsAdmin::API::Resources::User, value_label: :login
    resource VpsAdmin::API::Resources::UserNamespace, value_label: :id
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List user namespace maps'

    input do
      use :filters
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_namespaces: { user_id: u.id }
      input whitelist: %i[limit offset user_namespace]
      allow
    end

    def query
      q = self.class.model.joins(:user_namespace).where(with_restricted)

      %i[user_namespace].each do |v|
        q = q.where(v => input[v]) if input[v]
      end

      q = q.where(user_namespaces: { user_id: input[:user].id }) if input.has_key?(:user)

      q
    end

    def count
      query.count
    end

    def exec
      query.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_namespaces: { user_id: u.id }
      allow
    end

    def prepare
      @map = self.class.model.joins(:user_namespace).find_by!(with_restricted(
                                                                user_namespace_maps: { id: params[:user_namespace_map_id] }
                                                              ))
    end

    def exec
      @map
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create user namespace map'

    input do
      use :common
      patch :user_namespace, required: true
      patch :label, required: true
    end

    output do
      use :all
    end

    authorize do |_u|
      allow
    end

    def exec
      error!('access denied') if !current_user.role == :admin && input[:user_namespace].user_id != current_user.id

      UserNamespaceMap.create_direct!(input[:user_namespace], input[:label])
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Edit user namespace map'

    input do
      use :common, include: %i[user_namespace label]
      patch :user_namespace, required: true
      patch :label, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_namespaces: { user_id: u.id }
      allow
    end

    def exec
      map = self.class.model.joins(:user_namespace).find_by!(with_restricted(
                                                               id: params[:user_namespace_map_id]
                                                             ))

      map.update!(label: input[:label]) if input[:label]
      map
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete user namespace map'

    authorize do |u|
      allow if u.role == :admin
      restrict user_namespaces: { user_id: u.id }
      allow
    end

    def exec
      map = self.class.model.joins(:user_namespace).find_by!(with_restricted(
                                                               id: params[:user_namespace_map_id]
                                                             ))

      error!('the map is in use, unable to delete at this time') if map.in_use?

      map.acquire_lock do
        map.destroy!
      end

      ok!
    end
  end

  class Entry < HaveAPI::Resource
    desc 'Browse user namespace map entries'
    route '{user_namespace_map_id}/entries'
    model ::UserNamespaceMapEntry

    params(:all) do
      id :id, label: 'Entry ID'
      string :kind, choices: ::UserNamespaceMapEntry.kinds.keys.map(&:to_s)
      integer :vps_id, desc: 'Beginning of the ID range within VPS'
      integer :ns_id, desc: 'Beginning of the ID range within the user namespace'
      integer :count, desc: 'Number of mapped IDs'
    end

    params(:editable) do
      use :all, include: %i[vps_id ns_id count]
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List map entries'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_namespaces: { user_id: u.id }
        allow
      end

      def query
        self.class.model.joins(
          user_namespace_map: :user_namespace
        ).where(with_restricted(
                  user_namespace_maps: { id: params[:user_namespace_map_id] }
                ))
      end

      def count
        query.count
      end

      def exec
        query
          .order('user_namespace_map_entries.kind,user_namespace_map_entries.id')
          .limit(input[:limit])
          .offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_namespaces: { user_id: u.id }
        allow
      end

      def prepare
        @entry = self.class.model.joins(
          user_namespace_map: :user_namespace
        ).find_by!(with_restricted(
                     user_namespace_map_entries: { id: params[:entry_id] }
                   ))
      end

      def exec
        @entry
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a new map entry'

      input do
        arr = %i[kind vps_id ns_id count]

        use :all, include: arr
        arr.each { |v| patch v, required: true }
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_namespaces: { user_id: u.id }
        allow
      end

      def exec
        map = ::UserNamespaceMap.joins(:user_namespace).find_by!(with_restricted(
                                                                   user_namespace_maps: { id: params[:user_namespace_map_id] }
                                                                 ))

        if !current_user.role == :admin && map.user_namespace.user_id != current_user.id
          error!('access denied')

        elsif map.in_use?
          error!('the map is in use, it cannot be changed at this time')

        elsif map.user_namespace_map_entries.where(
          kind: ::UserNamespaceMapEntry.kinds[input[:kind]]
        ).count >= 10
          # ZFS properties uidmap/gidmap do not accept more than 10 entries
          # at the moment.
          error!('maps are limited to 10 UID and 10 GID entries')
        end

        map.acquire_lock do
          UserNamespaceMapEntry.create!(input.merge(user_namespace_map: map))
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Edit map entry'

      input do
        use :all, include: %i[vps_id ns_id count]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_namespaces: { user_id: u.id }
        allow
      end

      def exec
        entry = self.class.model.joins(
          user_namespace_map: :user_namespace
        ).find_by!(with_restricted(
                     user_namespace_map_entries: { id: params[:entry_id] }
                   ))

        error!('the map is in use, it cannot be changed at this time') if entry.user_namespace_map.in_use?

        entry.user_namespace_map.acquire_lock do
          entry.update!(input)
        end

        entry
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', to_param_names(e.record.errors.to_hash))
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete map entry'

      authorize do |u|
        allow if u.role == :admin
        restrict user_namespaces: { user_id: u.id }
        allow
      end

      def exec
        entry = self.class.model.joins(
          user_namespace_map: :user_namespace
        ).find_by!(with_restricted(
                     user_namespace_map_entries: { id: params[:entry_id] }
                   ))

        error!('the map is in use, it cannot be changed at this time') if entry.user_namespace_map.in_use?

        entry.user_namespace_map.acquire_lock do
          entry.destroy!
        end

        ok!
      end
    end
  end
end
