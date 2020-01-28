name             "artifact"
maintainer       "Riot Games"
maintainer_email "kallan@riotgames.com"
license          "Apache 2.0"
description      "Provides your cookbooks with the Artifact Deploy LWRP"
version          "14.0.3"

chef_version '>= 14.0'

supports "centos"
supports "redhat"
supports "fedora"
supports "ubuntu"

gem 'aws-sdk-s3'

# Moved this dependency into chef for better version control
# gem 'nexus_cli'
