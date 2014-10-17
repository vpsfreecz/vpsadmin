# Utilities for zfs
module Utils::Zfs
  # Shortcut for #syscmd
  def zfs(cmd, opts, component, valid_rcs = [])
    syscmd("#{$CFG.get(:bin, :zfs)} #{cmd.to_s} #{opts} #{component}", valid_rcs)
  end

  def list_snapshots(ds)
    zfs(:list, "-r -t snapshot -H -o name", ds)[:output].split()
  end
end
