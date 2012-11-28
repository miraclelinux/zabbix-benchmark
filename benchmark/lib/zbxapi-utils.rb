require 'zbxapi'

class Host < ZabbixAPI_Base
  action :create do
    add_valid_params("1.3",
                     ["host","port","status","useip",
                      "dns","ip","proxy_hostid",
                      "useipmi","ipmi_ip","ipmi_port", "ipmi_authtype",
                      "ipmi_privilege","ipmi_username", "ipmi_password",
                      "groups","templates"])
    add_valid_params("1.4",
                     ["host","status",
                      "proxy_hostid","useipmi","ipmi_ip","ipmi_port",
                      "ipmi_authtype","ipmi_privilege","ipmi_username",
                      "ipmi_password","groups","templates","interfaces"])
  end
end
