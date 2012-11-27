#
# Cookbook Name:: collectd
# Recipe:: default
#
# Copyright 2010, Atari, Inc
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

collectd_version = ''
collectd_package_name = ''

case node[:platform]
when "ubuntu"
  include_recipe "apt::default"

  package "python-software-properties" do
    action :upgrade
  end

  collectd_package_name = "collectd-core"

  case node[:platform_version].to_f
  when 10.04

    # install python dependency
    package "libpython2.6" do
      action :install
    end

    # setup a ppa to get a reasonable version of collectd
    ### this comes from CLA's PPAs
    
    #script "enable_ppa_jdub" do
    #  interpreter "bash"
    #  user "root"
    #  cwd "/tmp"
    #  code <<-EOH
    #    /usr/bin/add-apt-repository #{add_apt_repo_flags} ppa:jdub
    #  EOH
    #  not_if "/usr/bin/test -f /etc/apts/sources.list.d/jdub-ppa-lucid.list"
    #  notifies :run, "execute[apt_update]", :immediately
    #end
    
    
    # specify the version number to install
    collectd_version = "4.10.1-1~ppa1"
  when 12.04

    # install python dependency
    package "libpython2.7" do
      action :install
    end

    # specify the version number to install
    collectd_version = "4.10.1-2.1ubuntu7"
  end

  # common to all ubuntu versions
  execute "apt_update" do
    command "apt-get update"
    action :nothing
  end

  package "#{collectd_package_name}" do
    package_name collectd_package_name
    version collectd_version
  end

when "redhat", "centos"
  # we're going to need things from repoforge since collectd is in the default repo
  include_recipe "yum::default"
  ## copied to CLA repos that are active on the host, local mod
  #include_recipe "yum::repoforge"

  collectd_package_name = "collectd"

  if node[:kernel][:machine] == 'x86_64'
    collectd_version = 'x86_64'
  else
    collectd_version = 'i386' 
  end

  # install collectd
  yum_package "#{collectd_package_name}" do
    arch "#{collectd_version}"
    flush_cache [ :before ]
  end

  # fix the init script to avoid the python global problem
  cookbook_file "/tmp/collectd_centos58_init_patch" do
    source "centos58_init_patch"
    not_if "grep LD_PRELOAD= /etc/init.d/collectd"
    mode "0644"
    action :create
    notifies :run, "execute[patch_collectd_init]", :immediately
  end

  execute "patch_collectd_init" do
    command "/usr/bin/patch -N /etc/init.d/collectd < /tmp/collectd_centos58_init_patch"
    user "root"
    returns [0, 1]
    action :nothing
    notifies :run, "execute[rm_diff]", :delayed
  end

  execute "rm_diff" do
    # don't worry about return value on this
    command "/bin/rm /tmp/collectd_centos58_init_patch || true"
    action :nothing
  end
end

service "collectd" do
  action [:enable, :start]
end

directory node[:collectd][:plugin_config_dir] do
  owner "root"
  group "root"
  mode "755"
end

directory node[:collectd][:base_dir] do
  owner "root"
  group "root"
  mode "755"
  recursive true
end

directory node[:collectd][:plugin_dir] do
  owner "root"
  group "root"
  mode "755"
  recursive true
end

%w(collectd thresholds).each do |file|
  template "#{node[:collectd][:config_dir]}/#{file}.conf" do
    source "#{file}.conf.erb"
    owner "root"
    group "root"
    mode "644"
    notifies :restart, resources(:service => "collectd")
  end
end

ruby_block "delete_old_plugins" do
  block do
    Dir["#{node[:collectd][:plugin_config_dir]}/*.conf"].each do |path|
      autogen = false
      File.open(path).each_line do |line|
        if line.start_with?('#') and line.include?('autogenerated')
          autogen = true
          break
        end
      end
      if autogen
        begin
          resources(:template => path)
        rescue
          # If the file is autogenerated and has no template it has likely been removed from the run list
          Chef::Log.info("Deleting old plugin config in #{path}")
          File.unlink(path)
        end
      end
    end
  end
end

service "collectd" do
  action [:enable, :start]
end
