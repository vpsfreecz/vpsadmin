vpsAdmin Cop
============

This plugin allows admins to configure policies for resource usage and find
users that violate these policies.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory.

    $ rake vpsadmin:plugins:migrate PLUGIN=cop

## Usage
Policies are defined in `config/policies.rb` using a custom DSL. For example,
a policy that would check that users do not use more than 75% of CPU for three
days in a row:

    policy :cpu do
      label 'VPS CPU time'
      desc 'The VPS used more than 75% CPU for the last 3 days'

      # How long has the policy have to be violated
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

      # Check that an observed value does not violate this policy, i.e. the VPS
      # has more than 25% CPU idle
      check { |vps, v| v.nil? || v > 25 }
    end

Policies can then be checked with a rake task:

    $ rake vpsadmin:cop:check

Confirmed policy violations are sent to admins via e-mail using template
`policy_violation`. No automated policy enforcing is in place.
