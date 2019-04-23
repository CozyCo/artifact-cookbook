#
# Cookbook Name:: artifact
# Resource:: file
#
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
class Chef
  class Resource
    class ArtifactFile < Chef::Resource

      allowed_actions :create
      default_action :create

      property :path, String, :required => true, :name_attribute => true
      property :location, String
      property :checksum, String
      property :owner, String, :required => true, :regex => Chef::Config[:user_valid_regex]
      property :group, String, :required => true, :regex => Chef::Config[:user_valid_regex]
      property :download_retries, Integer, :default => 1
      property :after_download, Proc
      property :nexus_configuration, [Chef::Artifact::NexusConfiguration, nil], :default => Chef::Artifact::NexusConfiguration.from_data_bag

    end
  end
end