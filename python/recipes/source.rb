configure_options = node['python']['configure_options'].join(" ")
#make_options = node['python']['make_options'].join(" ")

packages = value_for_platform(
    ["centos","redhat","fedora"] => 
        {"default" => ["openssl-devel","bzip2-devel","zlib-devel","expat-devel","db4-devel","sqlite-devel","ncurses-devel","readline-devel"]},
    "default" => 
        ["libssl-dev","libbz2-dev","zlib1g-dev","libexpat1-dev","libdb-dev","libsqlite3-dev","libncursesw5-dev","libncurses5-dev","libreadline-dev"]
  )

packages.each do |dev_pkg|
  package dev_pkg
end

version = node['python']['version']
install_path = "#{node['python']['prefix_dir']}/lib/python#{version.split(/(^\d+\.\d+)/)}"

remote_file "#{Chef::Config[:file_cache_path]}/Python-#{version}.tar.bz2" do
  source "#{node['python']['url']}/#{version}/Python-#{version}.tar.bz2"
  checksum node['python']['checksum']
  mode "0644"
  not_if { ::File.exists?(install_path) }
end

bash "build-and-install-python" do
  cwd Chef::Config[:file_cache_path]
  code <<-EOF
  tar -jxvf Python-#{version}.tar.bz2
  (cd Python-#{version} && ./configure #{configure_options})
  (cd Python-#{version} && make && make install)
  EOF
  not_if { ::File.exists?(install_path) }
end
