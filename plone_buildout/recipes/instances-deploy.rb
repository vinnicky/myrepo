include_recipe "plone_buildout::instances"
app_name = node["plone_instances"]["app_name"]
return if !app_name
deploy = node[:deploy][app_name]

python_base_deploy do
  deploy_data deploy
  app_name app_name
end

# Update deploy
deploy = node[:deploy][app_name]

buildout_configure do
  deploy_data deploy
  app_name app_name
  force_build deploy["always_build_on_deploy"]
end
