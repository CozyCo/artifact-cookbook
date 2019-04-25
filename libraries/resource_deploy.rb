class Chef
  class Resource
    class ArtifactDeploy < Chef::Resource
      
      #
      # Cookbook Name:: artifact
      # Resource:: deploy
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

      require 'uri'

      allowed_actions :deploy, :pre_seed
      default_action :deploy

      property :artifact_name, String, :required => true, :name_attribute => true
      property :artifact_location, String
      property :artifact_checksum, String
      property :deploy_to, String, :required => true
      property :version, String, :required => true
      property :owner, String, :required => true, :regex => Chef::Config[:user_valid_regex]
      property :group, String, :required => true, :regex => Chef::Config[:user_valid_regex]
      property :environment, Hash, :default => Hash.new
      property :symlinks, Hash, :default => Hash.new
      property :shared_directories, Array, :default => %w{ system pids log }
      property :force, [ TrueClass, FalseClass ], :default => false
      property :should_migrate, [ TrueClass, FalseClass ], :default => false
      property :keep, Integer, :default => 2
      property :is_tarball, [ TrueClass, FalseClass ], :default => true
      property :before_deploy, Proc
      property :before_extract, Proc
      property :after_extract, Proc
      property :before_symlink, Proc
      property :after_symlink, Proc
      property :configure, Proc
      property :before_migrate, Proc
      property :after_migrate, Proc
      property :migrate, Proc
      property :restart, Proc
      property :after_deploy, Proc
      property :after_download, Proc
      property :remove_top_level_directory, [ TrueClass, FalseClass ], :default => false
      property :skip_manifest_check, [ TrueClass, FalseClass ], :default => false
      property :remove_on_force, [ TrueClass, FalseClass ], :default => false
      property :nexus_configuration, [Chef::Artifact::NexusConfiguration, nil], :default => Chef::Artifact::NexusConfiguration.from_data_bag

      def initialize(*args)
        super
        @action = :deploy
      end

      def artifact_deploys_cache_path
        ::File.join(Chef::Config[:file_cache_path], "artifact_deploys")
      end

      def current_path
        ::File.join(self.deploy_to, "current")
      end

      def shared_path
        ::File.join(self.deploy_to, "shared")
      end
    end
  end
end