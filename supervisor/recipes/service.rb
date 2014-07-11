#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: supervisor
# Provider:: service
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
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
actions :enable, :disable, :start, :stop, :restart, :reload

def initialize(*args)
  super
  @action = [:enable, :start]
end

attribute :service_name, :kind_of => String, :name_attribute => true
attribute :command, :kind_of => String
attribute :process_name, :kind_of => String, :default => '%(program_name)s'
attribute :numprocs, :kind_of => Integer, :default => 1
attribute :numprocs_start, :kind_of => Integer, :default => 0
attribute :priority, :kind_of => Integer, :default => 999
attribute :autostart, :kind_of => [TrueClass, FalseClass], :default => true
attribute :autorestart, :kind_of => [String, Symbol, TrueClass, FalseClass], :default => :unexpected
attribute :startsecs, :kind_of => Integer, :default => 1
attribute :startretries, :kind_of => Integer, :default => 3
attribute :exitcodes, :kind_of => Array, :default => [0, 2]
attribute :stopsignal, :kind_of => [String, Symbol], :default => :TERM
attribute :stopwaitsecs, :kind_of => Integer, :default => 10
attribute :user, :kind_of => [String, NilClass], :default => nil
attribute :redirect_stderr, :kind_of => [TrueClass, FalseClass], :default => false
attribute :stdout_logfile, :kind_of => String, :default => 'AUTO'
attribute :stdout_logfile_maxbytes, :kind_of => String, :default => '50MB'
attribute :stdout_logfile_backups, :kind_of => Integer, :default => 10
attribute :stdout_capture_maxbytes, :kind_of => String, :default => '0'
attribute :stdout_events_enabled, :kind_of => [TrueClass, FalseClass], :default => false
attribute :stderr_logfile, :kind_of => String, :default => 'AUTO'
attribute :stderr_logfile_maxbytes, :kind_of => String, :default => '50MB'
attribute :stderr_logfile_backups, :kind_of => Integer, :default => 10
attribute :stderr_capture_maxbytes, :kind_of => String, :default => '0'
attribute :stderr_events_enabled, :kind_of => [TrueClass, FalseClass], :default => false
attribute :environment, :kind_of => Hash, :default => {}
attribute :directory, :kind_of => [String, NilClass], :default => nil
attribute :umask, :kind_of => [NilClass, String], :default => nil
attribute :serverurl, :kind_of => String, :default => 'AUTO'

action :run do
  execute "supervisorctl update" do
    action :nothing
    user "root"
  end

  template "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
    source "program.conf.erb"
    cookbook "supervisor"
    owner "root"
    group "root"
    mode "644"
    variables :prog => new_resource
    notifies :run, resources(:execute => "supervisorctl update"), :immediately
  end
end

action :disable do
  execute "supervisorctl update" do
    action :nothing
    user "root"
  end

  file "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
    action :delete
    notifies :run, resources(:execute => "supervisorctl update"), :immediately
  end
end

action :start do
  execute "supervisorctl start #{new_resource.service_name}" do
    user "root"
  end
end

action :stop do
  execute "supervisorctl stop #{new_resource.service_name}" do
    user "root"
  end
end

action :restart  do
  execute "supervisorctl restart #{new_resource.service_name}" do
    user "root"
  end
end

action :reload  do
  execute "supervisorctl restart #{new_resource.service_name}" do
    user "root"
  end
end
