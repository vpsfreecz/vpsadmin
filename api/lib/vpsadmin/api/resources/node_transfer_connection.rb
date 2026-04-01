# frozen_string_literal: true

module VpsAdmin::API::Resources
  class NodeTransferConnection < HaveAPI::Resource
    model ::NodeTransferConnection
    desc 'Manage pairwise transfer-only node interconnects'

    params(:common) do
      resource Node, name: :node_a, value_label: :domain_name
      resource Node, name: :node_b, value_label: :domain_name
      string :node_a_ip_addr
      string :node_b_ip_addr
      bool :enabled
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List node transfer connections'

      input do
        resource Node, name: :node, value_label: :domain_name
        bool :enabled
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::NodeTransferConnection.order(:node_a_id, :node_b_id)
        q = q.where('node_a_id = :id OR node_b_id = :id', id: input[:node].id) if input[:node]
        q = q.where(enabled: input[:enabled]) if input.has_key?(:enabled)
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query.includes(:node_a, :node_b)))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show node transfer connection'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @conn = with_includes(
          ::NodeTransferConnection.includes(:node_a, :node_b).find(params[:node_transfer_connection_id])
        )
      end

      def exec
        @conn
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create node transfer connection'

      input do
        use :common
        patch :node_a, required: true
        patch :node_b, required: true
        patch :node_a_ip_addr, required: true
        patch :node_b_ip_addr, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::NodeTransferConnection.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique
        error!('create failed', node_a: ['connection for this node pair already exists'])
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update node transfer connection'

      input do
        use :common, include: %i[node_a_ip_addr node_b_ip_addr enabled]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        conn = ::NodeTransferConnection.find(params[:node_transfer_connection_id])
        conn.update!(input)
        conn
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete node transfer connection'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::NodeTransferConnection.find(params[:node_transfer_connection_id]).destroy!
        ok!
      end
    end
  end
end
