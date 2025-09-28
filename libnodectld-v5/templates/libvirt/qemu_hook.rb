#!/run/nodectl/nodectl script
require 'nodectld/standalone'

NodeCtld::QemuHook.run(ARGV)
