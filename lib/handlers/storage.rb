require 'lib/executor'

# Represents storage node, handles datasets and exports, supports only ZFS

class Storage < Executor
	# Create dataset
	# 
	# Params:
	# [dataset]       string; name of dataset
	# [share_options] string, optional; options passed directly to zfs sharenfs
	# [quota]         number; quota for this dataset, in bytes
	def create_ds
		zfs(:create, "-p", @params["dataset"])
		update_ds
	end
	
	# Update dataset
	# 
	# Params:
	# [dataset]       string; name of dataset
	# [share_options] string, optional; options passed directly to zfs sharenfs
	# [quota]         number; quota for this dataset, in bytes
	def update_ds
		zfs(:set, "sharenfs=\"#{@params["share_options"]}\"", @params["dataset"]) if @params["share_options"]
		zfs(:set, "quota=#{@params["quota"] == 0 ? "none" : @params["quota"]}", @params["dataset"])
	end
	
	# Shortcut for #syscmd
	def zfs(cmd, opts, component, valid_rcs = [])
		syscmd("#{$CFG.get(:bin, :zfs)} #{cmd.to_s} #{opts} #{component}", valid_rcs)
	end
end
