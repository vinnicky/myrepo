node.normal[:nginx][:client_max_body_size] = '128m'

# Store logs on large fast instance storage
directory '/mnt/var/log/nginx' do
  recursive true
  action :create
end

directory '/var/log/nginx' do
  action :create
end

mount '/var/log/nginx' do
  device '/mnt/var/log/nginx'
  fstype 'none'
  options "bind,rw"
  action [:mount, :enable]
end

include_recipe 'nginx'

template "#{node[:nginx][:dir]}/sites-available/instances" do
  source "instances.nginx.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, "service[nginx]", :delayed
end

link "#{node[:nginx][:dir]}/sites-enabled/default" do
  action :delete
end

link "#{node[:nginx][:dir]}/sites-enabled/instances" do
  to "#{node[:nginx][:dir]}/sites-available/instances"
  owner "root"
  group "root"
  mode 0644
end
