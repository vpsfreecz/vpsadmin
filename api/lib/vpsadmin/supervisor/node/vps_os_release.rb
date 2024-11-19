require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsOsRelease < Node::Base
    SKIP_IDS = %w[
      arch
      chimera
      gentoo
      guix
      opensuse-tumbleweed
      void
    ].freeze

    def self.setup(channel)
      channel.prefetch(5)
    end

    def start
      exchange = channel.direct(exchange_name)

      queue = channel.queue(
        queue_name('vps_os_releases'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_os_releases')

      queue.subscribe do |_delivery_info, _properties, payload|
        update_vps_os_release(JSON.parse(payload))
      end
    end

    protected

    def update_vps_os_release(os_release)
      t = Time.at(os_release['time'])

      name = os_release['os_release']['NAME']
      id = os_release['os_release']['ID']
      version_id = os_release['os_release']['VERSION_ID']

      # If VERSION_ID is not set, there is nothing to update.
      # For example, Debian testing/unstable does not have VERSION_ID set.
      # Rolling distributions are also skipped.
      return if version_id.nil? || SKIP_IDS.include?(id)

      # Translate VERSION_ID to template version
      tpl_distribution, tpl_version = os_release_to_template_version(name, id, version_id)

      # Find VPS
      vps = ::Vps.find_by!(id: os_release['vps_id'], enable_os_template_auto_update: true)

      # Proceed with update only if the distribution matches and the version does not
      return if vps.os_template.distribution != tpl_distribution \
                || vps.os_template.version == tpl_version

      # Find a new template
      new_template = ::OsTemplate.find_by!(
        distribution: vps.os_template.distribution,
        version: tpl_version,
        arch: vps.os_template.arch,
        vendor: vps.os_template.vendor,
        variant: vps.os_template.variant
      )

      # Set new template
      TransactionChains::Vps::Update.fire2(
        args: [vps, { os_template: new_template }],
        kwargs: { os_release: os_release['os_release'] }
      )
    rescue ActiveRecord::RecordNotFound
      # return
    rescue ResourceLocked => e
      warn "Unable to update OS template, resource locked: #{e.message}"
    end

    # Translate os-release versions to those used in vpsAdminOS container image repository
    #
    # os-release definitions differ slightly from how the default vpsAdminOS container
    # image repository is set up. Selected distribution names and versions are tweaked
    # to match the reposirory.
    #
    # See: https://github.com/vpsfreecz/vpsadminos/blob/staging/os/configs/image-repository.nix
    def os_release_to_template_version(name, id, version_id)
      case id
      when 'alpine'
        # x.y.z -> x.y
        [id, version_id.split('.')[0..-2].join('.')]

      when 'almalinux'
        if name.include?('Kitten')
          [id, "#{version_id}-kitten"]
        else
          # x.y -> x
          [id, version_id.split('.').first]
        end

      when 'centos'
        if name.include?('Stream')
          [id, "latest-#{version_id}-stream"]
        else
          [id, version_id]
        end

      when 'devuan'
        # Devuan < 4 in repo has version x.0; Devuan >= 4 has only x
        if version_id.to_i < 4
          [id, "#{version_id}.0"]
        else
          [id, version_id]
        end

      when 'opensuse-leap'
        ['opensuse', "leap-#{version_id}"]

      when 'rocky'
        # x.y -> x
        [id, version_id.split('.').first]

      else
        [id, version_id]
      end
    end
  end
end
