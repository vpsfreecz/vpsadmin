#!/usr/bin/env ruby
Dir.chdir('/opt/vpsadminapi')
$:.insert(0, '/opt/haveapi/lib')
require '/opt/vpsadminapi/lib/vpsadmin'

# A hash of minimum resources per environment. Key +nil+ is used when
# environment is not specified.
MINIMUM = {
#    3 => {
#        memory: 0,
#        swap: 0,
#        cpu: 0,
#        diskspace: 250 * 1024,
#        ipv4: 0,
#        ipv6: 0
#    },
    
    nil => {
        memory: 4096,
        swap: 0,
        cpu: 8,
        diskspace: 60 * 1024,
        ipv4: 1,
        ipv6: 32
    }
}

RESOURCES = %i(memory swap cpu diskspace ipv4 ipv6)

CONFIRMED = ClusterResourceUse.confirmed(:confirmed)

User.transaction do
  cluster_resources = {}

  ::ClusterResource.all.each do |cr|
    cluster_resources[cr.name.to_sym] = cr
  end

  User.all.find_each do |user|
    warn "User #{user.id} - #{user.login}"

    Environment.all.each do |env|
      warn "  * Environment #{env.label}"

      env_resources = {}

      # Create user cluster resources
      RESOURCES.each do |r|
        env_resources[r] = UserClusterResource.create!(
            user: user,
            cluster_resource: cluster_resources[r],
            environment: env,
            value: 0
        )
      end

      # User's VPSes
      user.vpses.includes(:dataset_in_pool).joins(:node).where(
          servers: {environment_id: env.id}
      ).each do |vps|
        warn "    - VPS #{vps.id}"

        vps_resources = {}
        delete_configs = []

        # Translate configs to cluster resources
        vps.vps_configs.each do |cfg|
          if /\Aram-vswap-(\d+)g-swap-0g\z/ =~ cfg.name
            vps_resources[:memory] = $~[1].to_i * 1024

          elsif /\Aswap-(\d+)g\z/ =~ cfg.name
            vps_resources[:swap] = $~[1].to_i * 1024

          elsif /\Acpu-(\d+)c-\d+\z/ =~ cfg.name
            vps_resources[:cpu] = $~[1].to_i

          elsif /\Ahdd-(\d+)g\z/ =~ cfg.name
            vps_resources[:diskspace] = $~[1].to_i * 1024

          else
            next
          end

          warn "        Config #{cfg.name}"

          # Mark config for deletion
          delete_configs << cfg
        end

        # Remove configs from the VPS
        delete_configs.each { |cfg| vps.vps_configs.delete(cfg) }

        # Count IP addresses
        [4, 6].each do |v|
          vps_resources[:"ipv#{v}"] = vps.ip_addresses.where(ip_v: v).count
        end

        vps_resources.each do |k, v|
          # Register cluster resource uses
          if k == :diskspace
            obj = vps.dataset_in_pool
            
            # Set dataset's property refquota
            vps.dataset_in_pool.refquota = v

          else
            obj = vps
          end

          use = ClusterResourceUse.new(
              class_name: obj.class.name,
              table_name: obj.class.table_name,
              row_id: obj.id,
              user_cluster_resource: env_resources[k],
              value: v,
              confirmed: CONFIRMED
          )
          use.save!(validate: false)

          warn "        #{k} = #{v}"
          
          # Sum
          env_resources[k].value += v
        end
      end

      # User's datasets on primary pools (NAS)
      DatasetInPool.joins(:dataset, pool: [:node]).includes(:dataset).where(
          datasets: {user_id: user.id},
          pools: {role: Pool.roles[:primary]},
          servers: {environment_id: env.id}
      ).each do |dip|
        quota = dip.quota

        warn "    - Dataset #{dip.dataset.full_name} #{quota / 1024} GiB"
        
        if dip.dataset.root?
          env_resources[:diskspace].value += quota
          
          use = ClusterResourceUse.new(
              class_name: dip.class.name,
              table_name: dip.class.table_name,
              row_id: dip.id,
              user_cluster_resource: env_resources[:diskspace],
              value: quota,
              confirmed: CONFIRMED
          )
          use.save!(validate: false)
          warn "        (is root)"
        end
      end

      # Apply minimums and save all user cluster resources
      warn "    = SUM"
      env_resources.each do |name, ucr|
        min = MINIMUM[env.id] ? MINIMUM[env.id][name] : MINIMUM[nil][name]
        ucr.value = min if ucr.value < min
    
        warn "      #{name} = #{ucr.value}"

        ucr.save!
      end
    end

    warn "\n------------\n\n"
  end
end

