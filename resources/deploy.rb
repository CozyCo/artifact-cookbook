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

actions :deploy, :pre_seed
default_action :deploy

attribute :artifact_name, :kind_of      => String, :required => true, :name_attribute => true
attribute :artifact_location, :kind_of  => String
attribute :deploy_to, :kind_of          => String, :required => true
attribute :version, :kind_of            => String, :required => true
attribute :owner, :kind_of              => String, :required => true, :regex => Chef::Config[:user_valid_regex]
attribute :group, :kind_of              => String, :required => true, :regex => Chef::Config[:user_valid_regex]
attribute :environment, :kind_of        => Hash, :default => Hash.new
attribute :symlinks, :kind_of           => Hash, :default => Hash.new
attribute :shared_directories, :kind_of => Array, :default => %w{ system pids log }
attribute :force, :kind_of              => [ TrueClass, FalseClass ], :default => false
attribute :keep, :kind_of               => Integer, :default => 2
attribute :is_tarball, :kind_of         => [ TrueClass, FalseClass ], :default => true
attribute :configure, :kind_of          => Proc
attribute :restart, :kind_of            => Proc
attribute :remove_top_level_directory, :kind_of => [ TrueClass, FalseClass ], :default => false
attribute :remove_on_force, :kind_of => [ TrueClass, FalseClass ], :default => false

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
