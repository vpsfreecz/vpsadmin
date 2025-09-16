# vmexec
`vmexec` is a tool to execute commands within libvirt domains using
QEMU Guest Agent.

`vmctexec` can be used to execute commands within the managed container
inside libvirt domains, i.e. it is a shortcut for running `lxc-attach`
with `vmexec`.
