vpsAdmin Monitoring
===================

This plugin allows admins to configure custom monitors for resource usage
and can execute custom actions, i.e. route monitoring alert notifications.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory.

    $ rake vpsadmin:plugins:migrate PLUGIN=monitoring

## Usage
Monitors are defined in `config/monitoring.rb` using a custom DSL. For example,
a monitor that would check that users do not use more than 75% of CPU for three
days in a row:

    VpsAdmin::API::Plugins::Monitoring.config do
      action :route_alert do |event|
        # Route a monitoring event. The concrete event type and templates are
        # registered by the deployment configuration.
        route_monitoring_alert!(event)
      end

      monitor :cpu do
        label 'VPS CPU time'
        desc 'The VPS used more than 75% CPU for the last 3 days'

        # How long has the event have to take
        period 3*24*60*60

        # Return a collection of objects that should be checked
        query do
            ::Vps.joins(:vps_current_status, :user).where(
                users: {object_state: ::User.object_states[:active]},
                vpses: {object_state: ::Vps.object_states[:active]},
                vps_current_statuses: {status: true},
            ).includes(:vps_current_status)
        end

        # Return observed value for one object from the collection
        value { |vps| vps.vps_current_status.cpu_idle }

        # Check that an observed value passes, i.e. more than 25% CPU is idle
        check { |vps, v| v.nil? || v > 25 }

        # Name of an action that is called when the event is confirmed
        action :route_alert
      end
    end

Monitoring is run by a rake task:

    $ rake vpsadmin:monitoring:check
