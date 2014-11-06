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
          return true if current_user.role == :admin
          return false unless obj.respond_to?(:maintenance_lock)

          lock = obj.maintenance_lock
          raise ResourceUnderMaintenance, (lock === true ? '' : lock.reason) if lock
        end
      end

      def self.included(resource)
        params = output_params

        resource::Index.output(&params)
        resource::Show.output(&params)

        resource.define_action(:SetMaintenance) do
          desc 'Set maintenance lock'
          route ':%{resource}_id/maintenance'
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
            obj = m.find(params[:"#{self.class.resource.to_s.demodulize.underscore}_id"])

            if input[:lock]
              lock = MaintenanceLock.new(
                  class_name: m.to_s,
                  row_id: obj.id,
                  reason: input[:reason],
                  user: current_user
              )

              if lock.lock!
                ok
              else
                error('already locked')
              end

            else
              lock = MaintenanceLock.find_by!(
                  class_name: m.to_s,
                  row_id: obj.id,
                  active: true
              )
              lock.unlock!
            end

          rescue ActiveRecord::RecordInvalid
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
        end
      end
    end

    # Include this module in model to enable maintenance lock support.
    module Model
      module ClassMethods
        # Set maintenance parent. When a lock for current object
        # is not found, its parent is checked.
        def maintenance_parent(klass = nil, &block)
          if klass
            @maintenance_parent = klass

          elsif block
            @maintenance_parent = block

          else
            @maintenance_parent
          end
        end
      end

      module InstanceMethods
        # Return MaintenanceLock object or boolean.
        def maintenance_lock(force = false)
          return @maintenance_lock_cache if !@maintenance_lock_cache.nil? && !force
          cls = self.class

          lock = MaintenanceLock.find_by(
              class_name: cls.to_s,
              row_id: self.id,
              active: true
          )

          @maintenance_lock_cache = lock

          return lock if lock

          parent = cls.maintenance_parent
          fail 'maintenance_parent not set' unless parent

          if parent.is_a?(Proc)
            @maintenance_lock_cache = parent.call

          else
            @maintenance_lock_cache = self.send(cls.maintenance_parent).maintenance_lock
          end
        end

        # :no, :lock, :master_lock
        def maintenance_lock?
          lock = maintenance_lock

          return :no unless lock
          return :master_lock if lock === true

          lock.class_name == self.class.to_s ? :lock : :master_lock
        end
      end

      def self.included(model)
        model.send(:extend, ClassMethods)
        model.send(:include, InstanceMethods)
      end
    end
  end
end
