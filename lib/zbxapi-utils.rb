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

class ZbxAPIUtils < ZabbixAPI
  MONITORED_HOST   = "0"
  UNMONITORED_HOST = "1"
  ENABLED_ITEM    = "0"
  DISABLED_ITEM   = "1"

  VALUE_TYPE_FLOAT   = 0
  VALUE_TYPE_STRING  = 1
  VALUE_TYPE_LOG     = 2
  VALUE_TYPE_INTEGER = 3
  VALUE_TYPE_TEXT    = 4

  SUPPORTED_VALUE_TYPES = [VALUE_TYPE_FLOAT,
                           VALUE_TYPE_STRING,
                           VALUE_TYPE_INTEGER]

  def initialize(uri, username, password)
    @uri = uri
    @username = username
    @password = password
    super(@uri)
  end

  def ensure_loggedin
    unless loggedin?
      login(@username, @password)
    end
  end

  def get_items(host, key = nil)
    item_params = {
      "host"   => host,
      "output" => ["itemid", "value_type"],
    }
    item_params.merge!({"filter" => { "key_" => key }}) if key
    item.get(item_params)
  end

  def get_items_range(hostnames)
    host_ids = get_host_ids(hostnames)
    host_ids = host_ids.collect { |id| id["hostid"] }
    item_params = {
      "hostids" => host_ids,
      "output"  => "shorten",
    }
    items = item.get(item_params)
    item_ids = items.collect { |item| item["itemid"].to_i }

    [item_ids.min, item_ids.max]
  end

  def get_host_id(name)
    params = {
      "filter" => { "host" => name },
    }
    hosts = host.get(params)
    if hosts.empty?
      nil
    else
      hosts[0]["hostid"]
    end
  end

  def get_host_ids(hostnames)
    ensure_loggedin
    params = {
      "filter" => { "host" => hostnames },
    }
    host.get(params)
  end

  def get_registered_test_hosts(group_name)
    ensure_loggedin
    groupid = get_group_id(group_name)
    params = {
      "groupids" => [groupid],
      "output" => ["hostid", "host"],
    }
    hosts = host.get(params)
    hosts.select { |host| host["host"] =~ /\ATestHost[0-9]+\Z/ }
  end

  def get_enabled_hosts
    ensure_loggedin
    params = {
      "filter" => { "status" => MONITORED_HOST },
      "output" => ["hostid", "host"],
    }
    host.get(params)
  end

  def get_enabled_test_hosts
    ensure_loggedin
    hosts = get_enabled_hosts
    hosts.select { |host| host["host"] =~ /\ATestHost[0-9]+\Z/ }
  end

  def get_enabled_items(hostids)
    item_params = {
      "filter"  => { "status" => ZbxAPIUtils::ENABLED_ITEM },
      "output"  => "shorten",
    }
    item_params["hostids"] ||= hostids
    item.get(item_params)
  end

  def get_template_id(name)
    params = {
      "filter" => { "host" => name, },
    }
    templates = template.get(params)
    templates[0]["templateid"]
  end

  def get_group_id(name)
    params = {
      "filter" => {
        "name" => name,
      },
    }
    groups = hostgroup.get(params)
    groups[0]["groupid"]
  end

  def create_host(host_name, group_name, template_name, agent, status)
    group_id = get_group_id(group_name)
    template_id = get_template_id(template_name)

    base_params = {
      "host" => host_name,
      "groups" =>
      [
       { "groupid" => group_id },
      ],
      "templates" =>
      [
       { "templateid" => template_id },
      ],
      "status" => status,
    }
    host_params = base_params.merge(iface_params(agent))

    host.create(host_params)

    p host_params
  end

  def delete_host(host_id)
    unless host_id.kind_of?(Fixnum)
      host_id = get_host_id(host_id)
    end
    return unless host_id

    delete_params =
      [
       {
         "hostid" => host_id,
       },
      ]
    host.delete(delete_params)
  end

  def set_host_statuses(hostnames, status)
    ensure_loggedin
    params = {
      "hosts"  => get_host_ids(hostnames),
      "status" => status,
    }
    host.massUpdate(params)
  end

  def enable_hosts(hostnames)
    set_host_statuses(hostnames, MONITORED_HOST)
  end

  def disable_hosts(hostnames)
    set_host_statuses(hostnames, UNMONITORED_HOST)
  end

  def get_history_by_key(host, key, begin_time, end_time)
    items = get_items(host, key)
    return nil if items.empty?

    get_history(items.first, begin_time, end_time)
  end

  def get_history(item, begin_time, end_time)
    item_id = item["itemid"]
    value_type = item["value_type"]
    history_params = {
      "history"   => value_type,
      "itemids"   => [item_id],
      "time_from" => begin_time.to_i,
      "time_till" => end_time.to_i,
      "output"    => "extend",
    }
    history.get(history_params)
  end

  def iface_params(agent)
    {
      "interfaces" =>
      [
       {
         "type"  => 1,
         "main"  => 1,
         "useip" => 1,
         "ip"    => agent["ip_address"],
         "dns"   => "",
         "port"  => agent["port"],
       },
      ],
    }
  end
end
