require 'json'
require 'open3'

module Vpsadminos
  class Error < StandardError; end

  module_function

  def repo_root
    @repo_root ||= File.realpath(File.join(__dir__, '..'))
  end

  def local_checkout?
    !ENV.fetch('VPSADMINOS_PATH', '').empty?
  end

  def local_path
    path = ENV.fetch('VPSADMINOS_PATH', '')
    return nil if path.empty?

    File.realpath(path)
  rescue Errno::ENOENT
    raise Error, "VPSADMINOS_PATH does not exist: #{path}"
  end

  def flake_input_path
    stdout, stderr, status = Open3.capture3(
      'nix', 'flake', 'archive', '--json', repo_root
    )

    unless status.success?
      detail = stderr.strip
      message = "Unable to resolve vpsadminos flake input from #{repo_root}"
      message += ": #{detail}" unless detail.empty?

      raise Error, message
    end

    path = JSON.parse(stdout).dig('inputs', 'vpsadminos', 'path')

    if path.nil? || path.empty?
      raise Error,
            'nix flake archive did not return inputs.vpsadminos.path for ' \
            "#{repo_root}"
    end

    File.realpath(path)
  rescue Errno::ENOENT
    raise Error,
          'Unable to run `nix flake archive`; install nix or set VPSADMINOS_PATH'
  rescue JSON::ParserError => e
    raise Error, "Unable to parse `nix flake archive` output: #{e.message}"
  end

  def source_path
    local_path || flake_input_path
  end

  def build_id
    build_id_path = File.join(source_path, '.build_id')
    File.read(build_id_path).strip
  rescue Errno::ENOENT
    raise Error, "vpsAdminOS build ID not found at '#{build_id_path}'"
  end

  def export_build_id_env!
    return if local_checkout?

    ENV['OS_BUILD_ID'] ||= build_id
  end
end
