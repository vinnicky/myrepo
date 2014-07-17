user node[:webserver][:user] do
  action :create
  home "/opt/#{node[:webserver][:user]}"
  manage_home true
  shell "/bin/bash"
end
