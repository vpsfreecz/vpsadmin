require 'ipaddress'

class AddNetworks < ActiveRecord::Migration
  class Network < ActiveRecord::Base
    belongs_to :location
    has_many :ip_addresses

    enum role: %i(public_access private_access)
  end

  class IpAddress < ActiveRecord::Base
    self.table_name = 'vps_ip'
    self.primary_key = 'ip_id'
  end

  def change
    @networks = []
    @orphans = []
    @net_map = {}

    reversible do |dir|
      dir.up do
        get_networks
        exit(false) unless continue?
      end
    end

    create_table :networks do |t|
      t.string      :label,               null: true, limit: 255
      t.references  :location,            null: false
      t.integer     :ip_version,          null: false
      t.string      :address,             null: false
      t.integer     :prefix,              null: false
      t.integer     :role,                null: false
      t.boolean     :partial,             null: false
      t.boolean     :managed,             null: false
    end

    add_index :networks, %i(location_id address prefix), unique: true

    add_column :vps_ip, :network_id, :integer, null: false
    add_index :vps_ip, :network_id

    reversible do |dir|
      dir.up do
        create_networks
        migrate_ips
      end

      dir.down do
        revert_ips
      end
    end

    remove_column :vps_ip, :ip_v, :integer, null: false
    remove_column :vps_ip, :ip_location, :integer, null: false
  end

  def get_networks
    puts
    puts "For the migration to take place, it needs to know what networks you have."
    puts "It is important to specify all networks, so that all IP addresses belong"
    puts "to one of them."
    puts
    puts "Enter the networks one by line, e.g. 192.168.1.0/24."
    puts "When finished, enter \"done\" and press enter."

    STDOUT.write('> ')
    STDOUT.flush
    STDIN.each_line do |line|
      s = line.strip
      next if s.empty?
      break if s.downcase == 'done'

      begin
        @networks << IPAddress.parse(s)

      rescue ArgumentError
        puts "'#{s}' is not a valid network"
      end

      STDOUT.write('> ')
      STDOUT.flush
    end

    puts "Done"
    puts
   
    used_nets = []

    IpAddress.all.each do |ip|
      ip_net = @networks.detect { |net| net.include?( IPAddress.parse(ip.ip_addr) ) }

      if ip_net
        used_nets << ip_net unless used_nets.include?(ip_net)

      else
        @orphans << ip
      end
    end

    if @orphans.any? || used_nets.count < @networks.count
      if used_nets.count < @networks.count
        puts "These networks are not used:"
        (@networks - used_nets).each { |net| puts "  #{net.to_string}" }
      end

      if @orphans.any?
        puts "The following IP addresses do not belong to any network, please restart"
        puts "the migration and specify all networks."
        puts
        @orphans.each { |ip| puts "  #{ip.ip_addr}" }
      end
      
      exit(false)
    end
  end

  def continue?
    puts
    puts "The migration can proceed with the following networks:"
    @networks.each { |net| puts "  #{net.to_string}" }
    puts
    STDOUT.write("Continue? [y/N]: ")
    STDOUT.flush
    return STDIN.readline.strip.downcase == 'y'
  end

  def create_networks
    @networks.each do |net|
      loc = nil

      IpAddress.all.each do |ip|
        if net.include?(IPAddress.parse(ip.ip_addr))
          loc = ip.ip_location
          break
        end
      end

      fail "cannot find location for network #{net.to_string}" unless loc

      @net_map[net] = Network.create!(
          location_id: loc,
          ip_version: net.ipv4? ? 4 : 6,
          address: net.to_s,
          prefix: net.prefix,
          role: 0,  # public
          partial: true,
          managed: true,
      )
    end
  end

  def migrate_ips
    IpAddress.all.each do |ip|
      addr = IPAddress.parse(ip.ip_addr)
      raw_net = @networks.detect { |net| net.include?(addr) }

      unless raw_net
        @orphans << ip
        next
      end

      net = @net_map[raw_net]

      if net.location_id != ip.ip_location
        fail "network location (#{net.location_id}) is not the same as IP location "+
             "(#{ip.ip_location})"
      end

      # IpAddress was first used when column network_id did not exist. It seems
      # unable to update it now.
      IpAddress.connection.execute(
          "UPDATE vps_ip SET network_id = #{net.id} WHERE ip_id = #{ip.id}"
      )
    end

    if @orphans.any?
      puts "The following IP addresses do not belong to any network, please restart"
      puts "the migration and specify all networks."
      puts
      @orphans.each { |ip| puts "  #{ip.ip_addr}" }
      puts
      puts "You can either fix this manually or rollback the migration and run it"
      puts "again."
    end
  end

  def revert_ips
    Network.all.each do |net|
      IpAddress.where(network_id: net.id).each do |ip|
        ip.update!(
            ip_v: net.ip_version,
            ip_location: net.location_id,
        )
      end
    end
  end
end
