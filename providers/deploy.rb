#
# Cookbook Name:: artifact
# Provider:: deploy
#
# Author:: Jamie Winsor (<jamie@vialstudios.com>)
# Author:: Kyle Allan (<kallan@riotgames.com>)
#
# Copyright 2013, Riot Games
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'digest'
require 'pathname'
require 'yaml'

attr_reader :release_path
attr_reader :current_path
attr_reader :shared_path
attr_reader :artifact_cache
attr_reader :artifact_cache_version_path
attr_reader :previous_version_paths
attr_reader :previous_version_numbers
attr_reader :artifact_location
attr_reader :artifact_version

include Chef::Artifact::Helpers

def load_current_resource

  if @new_resource.name =~ /\s/
    Chef::Log.warn "Whitespace detected in resource name. Failing Chef run."
    Chef::Application.fatal! "The name attribute for this resource is significant, and there cannot be whitespace. The preferred usage is to use the name of the artifact."
  end

  @artifact_version = @new_resource.version
  @artifact_location = @new_resource.artifact_location

  @release_path                = get_release_path
  @current_path                = @new_resource.current_path
  @shared_path                 = @new_resource.shared_path
  @artifact_cache              = ::File.join(@new_resource.artifact_deploys_cache_path, @new_resource.name)
  @artifact_cache_version_path = ::File.join(artifact_cache, artifact_version)
  @previous_version_paths      = get_previous_version_paths
  @previous_version_numbers    = get_previous_version_numbers
  @deploy                      = false
  @remove_on_force             = @new_resource.remove_on_force
  @current_resource            = Chef::Resource::ArtifactDeploy.new(@new_resource.name)

  @current_resource
end

action :deploy do
  delete_current_if_forcing!
  setup_deploy_directories!
  setup_shared_directories!

  @deploy = should_install? || artifact_changed?
  retrieve_artifact! if artifact_changed?

  if deploy?
    if new_resource.is_tarball
      extract_artifact!
    else
      copy_artifact
    end
    symlink_it_up!
  end

  run_proc :configure

  recipe_eval do
    link new_resource.current_path do
      to release_path
      owner new_resource.owner
      group new_resource.group
    end
  end

  if deploy?
    run_proc :restart
  end

  delete_previous_versions!

  new_resource.updated_by_last_action(true)
end

action :pre_seed do
  setup_deploy_directories!
  retrieve_artifact!
end

# Extracts the artifact defined in the resource call. Handles
# a variety of 'tar' based files (tar.gz, tgz, tar, tar.bz2, tbz)
# and a few 'zip' based files (zip, war, jar).
#
# @return [void]
def extract_artifact!
  recipe_eval do
    case ::File.extname(cached_tar_path)
    when /(tar|tgz|tar\.gz|tbz2|tbz|tar\.xz)$/

      taropts = [ '-x' ]
      taropts.push('-z') if cached_tar_path.match(/(tgz|tar\.gz)$/)
      taropts.push('-j') if cached_tar_path.match(/(tbz2|tbz)$/)
      taropts.push('-J') if cached_tar_path.match(/tar\.xz$/)
      taropts = taropts.join(' ')

      execute "extract_artifact!" do
        command "tar #{taropts} -f #{cached_tar_path} -C #{release_path}"
        user new_resource.owner
        group new_resource.group
        retries 2
      end
    when /zip$/
      package "unzip"
      execute "extract_artifact!" do
        command "unzip -q -u -o #{cached_tar_path} -d #{release_path}"
        user    new_resource.owner
        group   new_resource.group
        retries 2
      end
    when /(war|jar)$/
      ruby_block "Copy War/JAR File to Release_Path" do
        block do
          ::FileUtils.cp "#{cached_tar_path}", "#{release_path}"
        end
      end
    else
      Chef::Application.fatal! "Cannot extract artifact because of its extension. Supported types are [tar.gz tgz tar tar.bz2 tbz zip war jar]."
    end

    # Working with artifacts that are packaged under an extra top level directory
    # can be cumbersome. Remove it if a top level directory exists and the user
    # says to
    release_pathname = Pathname.new(release_path)
    ruby_block "remove top level" do
      block do
        top_level_dir = release_pathname.children.first.to_s
        ::FileUtils.mv(release_pathname.children.first.children, release_path)
        ::FileUtils.rm_rf(top_level_dir)
      end
      only_if do
        new_resource.remove_top_level_directory &&
          release_pathname.children.size == 1 &&
          release_pathname.children.first.directory?
      end
    end
  end
end

# Copies the artifact from its cached path to its release path. The cached path is
# the configured Chef::Config[:file_cache_path]/artifact_deploys
#
# @example
#   cp /tmp/vagrant-chef-1/artifact_deploys/artifact_test/1.0.0/my-artifact /srv/artifact_test/releases/1.0.0
#
# @return [void]
def copy_artifact
  recipe_eval do
    execute "copy artifact" do
      command "cp -R #{cached_tar_path} #{release_path}"
      user new_resource.owner
      group new_resource.group
    end
  end
end

# Returns the file path to the cached artifact the resource is installing.
#
# @return [String] the path to the cached artifact
def cached_tar_path
  ::File.join(artifact_cache_version_path, artifact_filename)
end

# Returns the filename of the artifact being installed when the LWRP
# is called, which is the basename of where the artifact is located.
#
# @example
#   When: new_resource.artifact_location => "http://some-site.com/my-artifact.jar"
#     artifact_filename => "my-artifact.jar"
#
# @return [String] the artifacts filename
def artifact_filename
  ::File.basename(artifact_location)
end

# Deletes the current version if and only if it is the same
# as the one to be installed, we are forcing, and remove_on_force is
# set. Only bad people will use this.
def delete_current_if_forcing!
  return unless @new_resource.force
  return unless remove_on_force?
  return unless get_current_release_version == artifact_version || previous_version_numbers.include?(artifact_version)

  recipe_eval do
    log "artifact_deploy[delete_current_if_forcing!] #{artifact_version} deleted because remove_on_force is true" do
      level :info
    end

    directory ::File.join(new_resource.deploy_to, 'releases', artifact_version) do
      recursive true
      action :delete
    end
  end
end

# Deletes released versions of the artifact when the number of
# released versions exceeds the :keep value.
def delete_previous_versions!
  recipe_eval do
    versions_to_delete = []

    keep = new_resource.keep
    delete_first = total = get_previous_version_paths.length

    if total == 0 || total <= keep
      true
    else
      delete_first -= keep
      Chef::Log.info "artifact_deploy[delete_previous_versions!] is deleting #{delete_first} of #{total} old versions (keeping: #{keep})"
      versions_to_delete = get_previous_version_paths.shift(delete_first)
    end

    versions_to_delete.each do |version|
      log "artifact_deploy[delete_previous_versions!] #{version.basename} deleted" do
        level :info
      end

      directory ::File.join(artifact_cache, version.basename) do
        recursive true
        action    :delete
      end

      directory ::File.join(new_resource.deploy_to, 'releases', version.basename) do
        recursive true
        action    :delete
      end
    end
  end
end

private
  def location_parts(location)
    group_id, artifact_id, extension, classifier, version = location.split(":")
    unless version
      version = classifier
      classifier = nil
    end
    [group_id, artifact_id, extension, classifier, version]
  end

  # A wrapper that calls Chef::Artifact:run_proc
  #
  # @param name     [Symbol] the name of the proc to execute
  #
  # @return [void]
  def run_proc(name)
    execute_run_proc("artifact_deploy", new_resource, name)
  end

  # Checks the various cases of whether an artifact has or has not been installed.
  #
  # @return [Boolean]
  def should_install?
    if new_resource.force
      Chef::Log.info "artifact_deploy: Force-installing version, #{artifact_version} for #{new_resource.name}."
      return true
    elsif get_current_release_version.nil? ||
          (artifact_version != get_current_release_version && !previous_version_numbers.include?(artifact_version))
      Chef::Log.info "artifact_deploy: Installing new version, #{artifact_version} for #{new_resource.name}."
      return true
    elsif artifact_version == get_current_release_version ||
          (artifact_version != get_current_release_version && previous_version_numbers.include?(artifact_version))
      Chef::Log.info "artifact_deploy: Version #{artifact_version} of artifact has already been installed."
      return false
    end
  end



  # @return [Boolean] the deploy instance variable
  def deploy?
    @deploy
  end

  # @return [Boolean] the remove_on_force instance variable
  def remove_on_force?
    @remove_on_force
  end

  # @return [String] the current version the current symlink points to
  def get_current_release_version
    get_current_deployed_version(new_resource.deploy_to)
  end

  # @return [Boolean] the current artifact is deployed using symlinks
  def is_current_using_symlinks?
    ::File.symlink? new_resource.current_path
  end

  # Returns a path to the artifact being installed by
  # the configured resource.
  #
  # @example
  #   When:
  #     new_resource.deploy_to = "/srv/artifact_test" and artifact_version = "1.0.0"
  #       get_release_path => "/srv/artifact_test/releases/1.0.0"
  #
  # @return [String] the artifacts release path
  def get_release_path
    ::File.join(new_resource.deploy_to, "releases", artifact_version)
  end

  # Searches the releases directory and returns an Array of version folders. After
  # rejecting the current release version from the Array, the array is sorted by mtime
  # and returned.
  #
  # @return [Array] the mtime sorted array of currently installed versions
  def get_previous_version_paths
    versions = Dir[::File.join(new_resource.deploy_to, "releases", '**')].collect do |v|
      Pathname.new(v)
    end

    versions.reject! { |v| v.basename.to_s == get_current_release_version }

    versions.sort_by(&:mtime)
  end

  # Convenience method for returning just the version numbers of
  # the currently installed versions of the artifact.
  #
  # @return [Array] the currently installed version numbers
  def get_previous_version_numbers
    previous_version_paths.collect { |version| version.basename.to_s}
  end

  # Creates directories and symlinks as defined by the symlinks
  # attribute of the resource.
  #
  # @return [void]
  def symlink_it_up!
    recipe_eval do
      new_resource.symlinks.each do |key, value|
        Chef::Log.info "artifact_deploy[symlink_it_up!] Creating and linking #{new_resource.shared_path}/#{key} to #{release_path}/#{value}"
        directory "#{new_resource.shared_path}/#{key}" do
          owner new_resource.owner
          group new_resource.group
          mode '0755'
          recursive true
        end

        link "#{release_path}/#{value}" do
          to "#{new_resource.shared_path}/#{key}"
          owner new_resource.owner
          group new_resource.group
        end
      end
    end
  end

  # Creates directories that are necessary for installing
  # the artifact.
  #
  # @return [void]
  def setup_deploy_directories!
    recipe_eval do
      [ artifact_cache_version_path, release_path, shared_path ].each do |path|
        Chef::Log.info "artifact_deploy[setup_deploy_directories!] Creating #{path}"
        directory path do
          owner new_resource.owner
          group new_resource.group
          mode '0755'
          recursive true
        end
      end
    end
  end

  # Creates directories that are defined in the shared_directories
  # attribute of the resource.
  #
  # @return [void]
  def setup_shared_directories!
    recipe_eval do
      new_resource.shared_directories.each do |dir|
        Chef::Log.info "artifact_deploy[setup_shared_directories!] Creating #{shared_path}/#{dir}"
        directory "#{shared_path}/#{dir}" do
          owner new_resource.owner
          group new_resource.group
          mode '0755'
          recursive true
        end
      end
    end
  end

  # Retrieves the configured artifact based on the
  # artifact_location instance variable.
  #
  # @return [void]
  def retrieve_artifact!
    recipe_eval do
      if ::File.exist?(new_resource.artifact_location)
        Chef::Log.info "artifact_deploy[retrieve_artifact!] Retrieving artifact local path #{artifact_location}"
        retrieve_from_local
      else
        Chef::Application.fatal! "artifact_deploy[retrieve_artifact!] Cannot retrieve artifact #{artifact_location}! Please make sure the artifact exists in the specified location."
      end
    end
  end

  # Defines a resource call for a file already on the file system.
  #
  # @return [void]
  def retrieve_from_local
    execute "copy artifact from #{new_resource.artifact_location} to #{cached_tar_path}" do
      command "cp -R #{new_resource.artifact_location} #{cached_tar_path}"
      user    new_resource.owner
      group   new_resource.group
      only_if { !::File.exists?(cached_tar_path) || !FileUtils.compare_file(new_resource.artifact_location, cached_tar_path) }
    end
  end

  def artifact_changed?
    !FileUtils.compare_file(new_resource.artifact_location, cached_tar_path)
  end

  # Returns the currently deployed version of an artifact given that artifacts
  # installation directory by reading what directory the 'current' symlink
  # points to.
  # if the 'current' directory is not a symlink, a ".symlinks" file is opened and the value
  # indicated by the 'current' key is returned.
  #
  # @param  deploy_to_dir [String] the directory where an artifact is installed
  # 
  # @example
  #   Chef::Artifact.get_current_deployed_version("/opt/my_deploy_dir") => "2.0.65"
  # 
  # @return [String] the currently deployed version of the given artifact
  def get_current_deployed_version(deploy_to_dir)

    current_dir = ::File.join(deploy_to_dir, "current")
    if ::File.exists?(current_dir)
      if ::File.symlink?(current_dir)
        ::File.basename(::File.readlink(current_dir))
      else
        symlinks_file = ::File.join(deploy_to_dir, ".symlinks")
        raise Exception, "error : file #{symlinks_file} doesn't exist" unless ::File.exist? symlinks_file
        YAML.load_file(symlinks_file)['current']
      end
    end
  end
