require 'rubygems'
require 'optparse'
require 'singleton'
require 'zbxapi'

class BenchmarkConfig
  include Singleton

  attr_accessor :api_uri, :login_user, :login_pass
  attr_accessor :num_hosts, :hosts_step, :host_group, :custom_agents

  def initialize
    @api_uri = "http://localhost/zabbix/"
    @login_user = "Admin"
    @login_pass = "zabbix"
    @num_hosts = 10
    @hosts_step = 0
    @host_group = "Linux servers"
    @custom_agents = []
    @default_agents = 
      [
       { :ip_address => "127.0.0.1", :port => 10050 },
      ]
  end

  def agents
    if @custom_agents.empty?
      @default_agents
    else
      @custom_agents
    end
  end

  def step
    step = @hosts_step > 0 ? @hosts_step : @num_hosts
  end

  def reset
    initialize
    self
  end
end

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

class Benchmark < ZabbixAPI
  def initialize
    @config = BenchmarkConfig.instance
    @last_status = {
      :time => nil,
      :level => -1
    }
    super(@config.api_uri)
    login(@config.login_user, @config.login_pass)
  end

  def setup
    setup_next_level
  end

  def cleanup
    puts "Remove all dummy hosts ..."

    groupid = get_group_id(@config.host_group)
    params = {
      "output" => "extend",
      "groupids" => [groupid],
    }
    hosts = host.get(params)

    hosts.each do |host_params|
      if host_params["host"] =~ /\ATestHost\d+\Z/
        puts "Remove #{host_params["host"]}"
        delete_host(host_params["hostid"].to_i)
      end
    end
  end

  def run
    until is_last_level do
      setup_next_level
      warm_up
      collect_data
    end
    cleanup
  end

  private
  def level_head
    level = @last_status[:level]
    @config.step * level
  end

  def level_tail
    tail = level_head + @config.step - 1
    tail < @config.num_hosts ? tail : @config.num_hosts
  end

  def n_hosts_in_level
    level_tail - level_head + 1
  end

  def is_last_level
    level_tail + 1 >= @config.num_hosts
  end

  def setup_next_level
    @last_status[:level] += 1

    puts "Register #{n_hosts_in_level} dummy hosts ..."

    level_head.upto(level_tail) do |i|
      host_name = "TestHost#{i}"
      agent = @config.agents[i % @config.agents.length]
      create_host(host_name, agent)
    end

    puts ""

    @last_status[:time] = Time.now
  end

  def warm_up
    print "warm_up\n\n"
    sleep 10
  end

  def collect_data
    print "collect_data\n\n"
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

  def get_template_id(name)
    params = {
      "filter" => { "host" => name, },
    }
    templates = template.get(params)
    case self.API_version
    when "1.2", "1.3"
      templates.keys[0]
    else
      templates[0]["templateid"]
    end
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

  def create_host(host_name, agent = nil)
    agent ||= @config.agents[0]

    group_name = @config.host_group
    group_id = get_group_id(group_name)
    template_name = default_linux_template_name
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
    }
    host_params = base_params.merge(iface_params(agent))

    host.create(host_params)

    p host_params
  end

  def delete_host(host_id)
    if host_id.kind_of?(String)
      host_id = get_host_id(host_name)
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

  def default_linux_template_name
    case self.API_version
    when "1.2", "1.3"
      "Template_Linux"
    else
      "Template OS Linux"
    end
  end

  def iface_params(agent)
    case self.API_version
    when "1.2", "1.3"
      {
        "ip" => agent[:ip_address],
        "port" => agent[:port],
        "useip" => 1,
        "dns" => "",
      }
    else
      {
        "interfaces" =>
        [
         {
           "type" => 1,
           "main" => 1,
           "useip" => 1,
           "ip" => agent[:ip_address],
           "dns" => "",
           "port" => agent[:port],
         },
        ],
      }
    end
  end
end
