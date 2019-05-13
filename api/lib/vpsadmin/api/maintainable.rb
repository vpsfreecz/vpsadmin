module VpsAdmin::API
  # Controller and model maintenance support.
  module Maintainable
    class ResourceUnderMaintenance < StandardError ; end

    # Include this module in resource controller to enable maintenance
    # lock support.
    # Index and Show actions must be defined for this module to work.
    module Action
      module InstanceMethods
        def maintenance_check!(obj)
          if (respond_to?(:current_user) && current_user.role == :admin) || User.current.role == :admin
            return true
          end

          return false unless obj.respond_to?(:maintenance_lock)

          if obj.maintenance_lock != MaintenanceLock.maintain_lock(:no)
            raise ResourceUnderMaintenance, obj.maintenance_lock_reason
          end
        end
      end

      def self.included(resource)
        params = output_params

        resource.const_defined?(:Index) && resource::Index.output(&params)
        resource.const_defined?(:Show) && resource::Show.output(&params)

        resource.define_action(:SetMaintenance) do
          desc 'Set maintenance lock'
          route ->(r){ r.singular ? 'set_maintenance' : '{%{resource}_id}/set_maintenance' }
          http_method :post

          input(:hash) do
            bool :lock, required: true
            string :reason, label: 'Reason', default: '', fill: true
          end

          authorize do |u|
            allow if u.role == :admin
          end

          def exec
            m = self.class.model
            res = self.class.resource
            obj = res.singular ? nil : m.find(params[:"#{res.to_s.demodulize.underscore}_id"])

            if input[:lock]
              lock = MaintenanceLock.new(
                class_name: (m && m.to_s) || res.to_s.demodulize.classify,
                row_id: obj && obj.id,
                reason: input[:reason],
                user: current_user
              )

              if lock.lock!(obj)
                ok
              else
                error('already locked')
              end

            else
              lock = MaintenanceLock.find_by!(
                class_name: (m && m.to_s) || res.to_s.demodulize.classify,
                row_id: obj && obj.id,
                active: true
              )
              lock.unlock!(obj)
            end

          rescue ActiveRecord::RecordInvalid => e
            puts e.message
            puts e.backtrace
            error('lock failed', lock.errors.to_hash)
          end
        end

        HaveAPI::Action.send(:include, InstanceMethods)
      end

      def self.output_params
        Proc.new do
          string :maintenance_lock, label: 'Maintenance lock',
                 choices: %i(no lock master_lock),
                 db_name: :maintenance_lock?
          string :maintenance_lock_reason, label: 'Maintenance reason'
        end
        # Proc.new {}
      end
    end

    # Include this module in model to enable maintenance lock support.
    module Model
      module ClassMethods
        # Set maintenance parents. When a lock for current object
        # is not found, its parent is checked.
        def maintenance_parents(*args, &block)
          if args.size > 0
            @maintenance_parents = args

          elsif block
            @maintenance_parents = block

          else
            @maintenance_parents
          end
        end

        # Set maintenances children. Should be names of AR associations.
        def maintenance_children(*args)
          if args.empty?
            @maintenance_children
          else
            @maintenance_children = args
          end
        end
      end

      module InstanceMethods
        # Return MaintenanceLock object or boolean.
        def find_maintenance_lock(force = false)
          return @maintenance_lock_cache if !@maintenance_lock_cache.nil? && !force
          cls = self.class

          lock = ::MaintenanceLock.find_by(
            class_name: cls.to_s,
            row_id: is_a?(ActiveRecord::Base) ? self.id : nil,
            active: true
          )

          @maintenance_lock_cache = lock

          return lock if lock

          parent = cls.maintenance_parents
          return false unless parent

          if parent.is_a?(::Proc)
            @maintenance_lock_cache = parent.call

          else
            cls.maintenance_parents.each do |p|
              parent_obj = self.send(p)
              @maintenance_lock_cache = parent_obj.find_maintenance_lock if parent_obj
              return @maintenance_lock_cache if @maintenance_lock_cache
            end

            @maintenance_lock_cache
          end
        end

        # :no, :lock, :master_lock
        def maintenance_lock?
          ::MaintenanceLock.maintain_lock(maintenance_lock)
        end
      end

      def self.included(model)
        model.send(:extend, ClassMethods)
        model.send(:include, InstanceMethods)
      end
    end

    # Include in any class in which maintenance_check! must be called.
    module Check
      def self.included(klass)
        klass.send(:extend, Action::InstanceMethods)
        klass.send(:include, Action::InstanceMethods)
      end
    end
  end
end
