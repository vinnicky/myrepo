#
# Basic server config: basic users, packages, etc.
#

### Packages
# Just base packages required by the whole system here, please. Dependencies
# for other recipes should live int hose recipes.

node[:deploy].each do |application, deploy|
  if deploy["custom_type"] != 'python'
    next
  end
  python_base_setup do
    deploy_data deploy
    app_name application
  end
end
