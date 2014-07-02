app_name =  node["plone_instances"]["app_name"]
Chef::Log.info("Running instances for #{app_name}")
return if !app_name

# Replace deploy if nil
node.default[:deploy][app_name] = {} if !node[:deploy][app_name]
deploy = node[:deploy][app_name]

py_version = deploy["python_major_version"]
old_custom_py = py_version && py_version == "2.4"

instance_data = node["plone_instances"]
# Backend factor is 1/8 of standard CPU it appears
instances = (node[:opsworks][:instance][:backends].to_i * instance_data["per_cpu"].to_f/8).ceil if node[:opsworks][:instance][:backends]
instances = (node[:cpu][:total].to_i * instance_data["per_cpu"].to_f).ceil if !node[:opsworks][:instance][:backends]
instances = 1 if instances < 1 || !instances
Chef::Log.info("Calculated instance count #{instances}.  Based on Backends: #{node[:opsworks][:instance][:backends]} CPUs: #{node[:cpu][:total]} and per_cpu config: #{instance_data["per_cpu"]}")
extra_parts = Array.new
additional_config = ""
extends = [instance_data["base_config"]]

if instance_data["enable_relstorage"]
  storage = instance_data["relstorage"]
  extends.push(storage['config'])
  db = storage["db"]
  storage_config = "\n[relstorage]"
  if db["dsn"]
    # If we have an explicit DSN, then use it along with the db type
    storage_config << "\n" << "db-type = #{db["type"]}" << "\n" << "dsn = #{db["dsn"]}"
  else
    # Otherwise we use the default DB (Postgres) and DSN
    storage_config << "\n" << "dbname = #{db["name"]}" << "\n" << "host = #{db["host"]}" 
    storage_config << "\n" << "user = #{db["user"]}" << "\n" << "password = #{db["password"]}"
  end
  # Memcached cache config
  if storage["enable_cache"]
    cache_servers = nil
    additional_config << "\n" << "eggs +="<< "\n" << "    pylibmc"
    case db["type"]
    when nil || 'postgres'
      driver = 'psycopg2'
    when 'mysql'
      driver = 'MySQL-python'
    when 'oracle'
      # This one needs libs not available through standard means,
      # you're on your own with that setup
      driver = 'cx_Oracle'
    else
      driver = nil
    end
    if driver
      additional_config << "\n" << "    #{driver}"
    end
    if storage["cache_servers"]
      cache_servers = storage["cache_servers"]
    elsif node[:opsworks] && node[:opsworks][:layers] && node[:opsworks][:layers]["memcached"] && node[:opsworks][:layers]["memcached"][:instances]
      cache_listing = []
      node[:opsworks][:layers]["memcached"][:instances].each {
        |name, instance| cache_listing.push("#{instance[:public_dns_name] || instance[:private_dns_name]}:11211") if instance[:status] == "online"
      }
      cache_servers = cache_listing.join(" ")
    end
    if cache_servers
      # Would be nice to order these based on the instance AZ, so that
      # the closer one is preferred, or perhaps so that only the
      # co-zoned cache is specified
      # We set a poll-interval if we are using caches
      storage_config << "\n" << "poll-interval = 60"
      # BBB
      storage_config << "\n" << "cache-servers = ${memcached:servers}"
      # The actual setting
      storage_config << "\n" << '[memcached]' << "\n" << "servers = #{cache_servers}"
    end
  end
  # Packing to be enabled on only one instance
  if storage["enable_pack"]
    extra_parts.push("pack-config")
    if storage["two_stage_pack"]
          extra_parts.push("zodbpack-prepack", "zodbpack-pack")
    else
      extra_parts.push("zodbpack")
    end
    storage_config << "\n" << "[zodbpack]" << "\n" << "pack-days = #{storage["pack_days"]}"
  end
else
  storage = instance_data["zeo"]
  storage_config = ''
  address = nil
  zeo_layer = instance_data["zeo_layer"]
  if instance_data["zeo"]["address"]
    address = instance_data["zeo"]["address"]
  elsif node[:opsworks] && node[:opsworks][:layers] && node[:opsworks][:layers][zeo_layer] && node[:opsworks][:layers][zeo_layer][:instances]
    instance_name, zeo_instance = node[:opsworks][:layers][zeo_layer][:instances].detect {
      |name, instance| instance[:status] == "online"
    }
    address = "#{zeo_instance[:public_dns_name] || zeo_instance[:private_dns_name]}:8001" if zeo_instance
  end
  if address
    storage_config << "\n" << '[zeo-host]'
    storage_config << "\n" << "address = #{address}"
    # BBB
    storage_config << "\n" << '[zeoserver]'
    storage_config << "\n" << 'address = ${zeo-host:address}'
  end
end

if instance_data["solr_enabled"] && node[:opsworks]
  solr_layer = instance_data["solr_layer"]
  if instance_data["solr_host"]
    # Update solr environment
    storage_config << "\n" << "[solr-host]" << "\n" << "host = #{instance_data["solr_host"]}"
  elsif  node[:opsworks] && node[:opsworks][:layers] && node[:opsworks][:layers][solr_layer] &&  node[:opsworks][:layers][solr_layer][:instances]
    instance_name, solr_instance = node[:opsworks][:layers][solr_layer][:instances].detect {
      |name, instance| instance[:status] == "online"
    }
    if solr_instance
      storage_config << "\n" << "[solr-host]" << "\n" << "host = #{solr_instance[:public_dns_name] || solr_instance[:private_dns_name]}"
    end
  end
end

init_commands = []

# Add any init commands explicitly added in the Stack JSON
init_commands.concat(deploy["buildout_init_commands"]) if deploy["buildout_init_commands"]

# Always add an egg cache environment in case we have cached zipped eggs, extract them in place
environment = {"PYTHON_EGG_CACHE" => ::File.join(deploy[:deploy_to], "shared", "eggs")}

client_config = "\n[client1]"
client_config << "\n" << "shared_blob = off" if !instance_data["shared_blobs"]
client_config << "\n" << "zeo-client-client = zeoclient-1" if instance_data["persistent_cache"]
client_config << "\n" << "zodb-cache-size = #{instance_data["zodb_cache_size"]}" if instance_data["zodb_cache_size"]
client_config << "\n" << "zserver-threads = #{instance_data["zserver_threads"]}" if instance_data["zserver_threads"]
# Turn off http-fast listen to keep the load balancer happy
# but not for old zope, which does not support fast-listen
if not old_custom_py
    client_config << "\n" << "http-fast-listen = off"
end

node.normal[:deploy][app_name]["environment"] = environment.update(deploy[:environment] || {})
# Add environment variables to client config, enforce ordering
client_config << "\n" << "environment-vars +="
(node[:deploy][app_name]["environment"].sort_by { |key, value| key.to_s }).each { |item| client_config << "\n    #{item[0]} #{item[1]}" if !item[0].match(/^(TMP|TEMP|RUBY|RAILS|RACK)/) }
Chef::Log.debug("Merged environment: #{node[:deploy][app_name]["environment"]}")

# client1 is already defined in the base configs.  Add more parts
# based on cpu count or explicit specification, and put them all in
# init.
1.upto(instances) do |n|
  part = "client#{n}"
  extra_parts.push(part)
  init_commands.push({'name' => part, 'cmd' => "bin/#{part}", 'args' => "console",
                      'delay' =>  instance_data['restart_delay']})
  if n != 1
    client_config << "\n" << "[#{part}]" << "\n" << "<= client1"
    # Hopefully we don't see port conflicts using this caclulation
    client_config << "\n" << "http-address = #{8080 + n}"
    client_config << "\n" << "zeo-client-client = zeoclient-#{n}" if instance_data["persistent_cache"]
  end
end

if instance_data["enable_celery"]
  broker_layer = instance_data["broker_layer"]
  port = instance_data['broker']['port']
  host = instance_data["broker"]["host"] if instance_data["broker"]["host"]
  if !host && node[:opsworks] && node[:opsworks][:layers] && node[:opsworks][:layers][broker_layer] &&  node[:opsworks][:layers][broker_layer][:instances]
    instance_name, broker_instance = node[:opsworks][:layers][broker_layer][:instances].detect {
      |name, instance| instance[:status] == "online"
    }
    if broker_instance
      host = broker_instance[:public_dns_name] || broker_instance[:private_dns_name]
    end
  end
  if host
    extra_parts.push("celery")
    storage_config << "\n" << "[celery-broker]" << "\n" << "host = #{host}"
    storage_config << "\n" << "port = #{port}"
    # For BBB with existing deployments
    storage_config << "\n" << '[celery]' << "\n" << 'broker-host = ${celery-broker:host}'
    storage_config << "\n" << 'broker-port = ${celery-broker:port}'
    celery_cmd = 'worker'
    init_commands.push({'name' => "celery", 'cmd' => 'bin/celery', 'args' => celery_cmd})
    if instance_data['celerybeat']
      init_commands.push({'name' => "celerybeat", 'cmd' => 'bin/celerybeat'})
    end
  end
end

node.normal[:deploy][app_name]["buildout_init_commands"] = init_commands
node.normal[:deploy][app_name]["buildout_init_type"] = :supervisor if !deploy["buildout_init_type"]
Chef::Log.debug("Merged supervisor init_commands: #{node[:deploy][app_name]["buildout_init_commands"]}")

# This is really a setup step, but setup may be to early to find the mount, in which case it is skipped and run again later during configure.
if instance_data["nfs_blobs"] || instance_data["gluster_blobs"]
  blob_mounts do
    deploy_data deploy
    use_gluster instance_data["gluster_blobs"]
  end
elsif instance_data["shared_blobs"] && node["plone_blobs"]["blob_dir"]
  # Create the blob dir if it doesn't exist, and give it "safe" permissions
  directory node["plone_blobs"]["blob_dir"] do
    owner deploy[:user]
    group deploy[:group]
    mode 0700
    recursive true
    action :create
  end
  blob_location = ::File.join(deploy[:deploy_to], 'shared', 'var', 'blobstorage')
  if node["plone_blobs"]["blob_dir"] != blob_location
    directory ::File.join(deploy[:deploy_to], 'shared', 'var') do
      owner deploy[:user]
      group deploy[:group]
      mode 0755
      recursive true
      action :create
    end
    link blob_location do
      to node["plone_blobs"]["blob_dir"]
    end
  end
end

orig_config = deploy["buildout_additional_config"] || ""

additional_config << orig_config << storage_config << client_config

node.normal[:deploy][app_name]["buildout_extends"] = extends.concat(deploy["buildout_extends"] || [])
Chef::Log.debug("Merged extends: #{node[:deploy][app_name]["buildout_extends"]}")
node.normal[:deploy][app_name]["buildout_parts_to_include"] = extra_parts.concat(deploy["buildout_parts_to_include"] || [])
Chef::Log.debug("Merged extra_parts: #{node[:deploy][app_name]["buildout_parts_to_include"]}")
node.normal[:deploy][app_name]["buildout_additional_config"] = additional_config
Chef::Log.debug("Merged additional_config: #{node[:deploy][app_name]["buildout_additional_config"]}")

# Enable recipe
node.normal[:deploy][app_name]["custom_type"] = "buildout"
