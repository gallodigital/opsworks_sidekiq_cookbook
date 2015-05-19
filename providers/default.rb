#
# Cookbook Name:: sidekiq
# Provider:: default
#
# Copyright 2012, Wanelo, Inc.
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

action :create do
  name       = new_resource.name
  user       = new_resource.user
  group      = new_resource.group
  rails_root = new_resource.working_directory
  envs       = new_resource.environment

  service_name = new_resource.include_prefix ? "sidekiq-#{name}" : name

  rails_env = new_resource.rails_env || node['sidekiq']['rails_env']
  config_dir = new_resource.config_dir || node['sidekiq']['config_dir']
  pid_dir = new_resource.pid_dir || node['sidekiq']['pid_dir']
  log_dir = new_resource.log_dir || node['sidekiq']['log_dir']

  pid_file = "#{pid_dir}/#{name}.pid"
  config_file = "#{config_dir}/#{name}.yml"
  log_file = "#{log_dir}/sidekiq-#{name}.log"

  execute "reload-monit-for-sidekiq" do
    command "monit -Iv reload"
    action :nothing
  end

  directory config_dir do
    mode 0755
  end

  directory pid_dir do
    owner user
    group group
    mode 0775
  end

  directory log_dir do
    mode 0775
  end

  %w{start quiet stop}.each do |phase|
    file "#{log_dir}/#{name}_#{phase}.log" do
      owner user
      group group
      mode 0755
      action :create_if_missing
    end
  end

  file log_file do
    owner user
    group group
    mode 0755
    action :create_if_missing
  end

  template "/etc/logrotate.d/sidekiq_#{name}" do
    source 'logrotate.erb'
    owner 'root'
    group 'root'
    variables 'log_dir' => log_dir
    mode 0644
  end

  template config_file do
    source 'config.yml.erb'
    cookbook 'opsworks_sidekiq'
    owner user
    group group
    mode 0755
    variables 'verbose' => new_resource.verbose,
              'concurrency' => new_resource.concurrency,
              'processes' => new_resource.processes,
              'sidekiq_timeout' => new_resource.sidekiq_timeout,
              'pid_file' => pid_file,
              'queues' => new_resource.queues
  end

  template "/usr/local/bin/stop_sidekiq_#{name}.sh" do
    source 'stop_sidekiq.sh.erb'
    cookbook 'opsworks_sidekiq'
    owner user
    group group
    mode 0755
    variables "pid_file" => pid_file,
              "log_dir" => log_dir,
              "user" => user,
              "name" => name,
              "rails_root" => rails_root
  end

  template "/usr/local/bin/start_sidekiq_#{name}.sh" do
    source 'start_sidekiq.sh.erb'
    cookbook 'opsworks_sidekiq'
    owner user
    group group
    mode 0755
    variables "rails_env" => rails_env,
              "config_file" => config_file,
              "pid_file" => pid_file,
              "log_file" => log_file,
              "log_dir" => log_dir,
              "user" => user,
              "name" => name,
              "rails_root" => rails_root,
              "environment" => envs
  end

  template "#{node.default["monit"]["conf_dir"]}/sidekiq_#{name}.monitrc" do
    source 'sidekiq.monitrc.erb'
    cookbook 'opsworks_sidekiq'
    owner 'root'
    group 'root'
    mode '0644'
    variables "name" => name,
              "pid_file" => pid_file
    notifies :run, "execute[reload-monit-for-sidekiq]", :immediately # Run immediately to ensure the following command works
  end

  # Restart sidekiq if it's already running
  execute "restart-sidekiq-service" do
    command "monit -Iv restart sidekiq_#{name}"
    only_if { ::File.exists?(pid_file) }
  end

  new_resource.updated_by_last_action(true)
end
