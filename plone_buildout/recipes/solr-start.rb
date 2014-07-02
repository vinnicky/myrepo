include_recipe "plone_buildout::solr"
app_name = node["plone_solr"]["app_name"]
return if !app_name
deploy = node[:deploy][app_name]

buildout_configure do
  deploy_data deploy
  app_name app_name
  run_action [:start]
end
