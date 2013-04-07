# Utilities for zfs
module ZfsUtils
	# Shortcut for #syscmd
	def zfs(cmd, opts, component, valid_rcs = [])
		syscmd("#{$CFG.get(:bin, :zfs)} #{cmd.to_s} #{opts} #{component}", valid_rcs)
	end
end
