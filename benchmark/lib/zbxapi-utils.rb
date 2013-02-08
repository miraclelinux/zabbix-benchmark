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
  ENABLED_ITEMS    = "0"
  DISABLED_ITEMS   = "1"

  attr_accessor :max_retry

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
      "host" => host,
      "output" => "shorten",
    }
    item_params.merge!({"filter" => { "key_" => key }}) if key
    item.get(item_params)
  end

  def get_items_range(hostnames)
    host_ids = get_host_ids(hostnames)
    host_ids = host_ids.collect { |id| id["hostid"] }
    item_params = {
      "hostids" => host_ids,
      "output" => "shorten",
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
      "hosts" => get_host_ids(hostnames),
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

  def get_history(host, key, begin_time, end_time)
    items = get_items(host, key)
    return nil if items.empty?

    item_id = items[0]["itemid"]
    value_type = items[0]["value_type"]
    history_params = {
      "history" => value_type,
      "itemids" => [item_id],
      "time_from" => begin_time,
      "time_till" => end_time,
      "output" => "extend",
    }
    history.get(history_params)
  end

  def iface_params(agent)
    {
      "interfaces" =>
      [
       {
         "type" => 1,
         "main" => 1,
         "useip" => 1,
         "ip" => agent["ip_address"],
         "dns" => "",
         "port" => agent["port"],
       },
      ],
    }
  end
end
