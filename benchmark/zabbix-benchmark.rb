#!/usr/bin/env ruby
require 'rubygems'
require 'optparse'
require 'singleton'
require 'zbxapi'

class BenchmarkConfig
  include Singleton

  attr_accessor :api_uri, :login_user, :login_pass, :dummy_host_count

  def initialize
    @api_uri = "http://localhost/zabbix/"
    @login_user = "Admin"
    @login_pass = "zabbix"
    @dummy_host_count = 10
  end
end

OptionParser.new do |options|
  config = BenchmarkConfig.instance

  options.on("-u", "--uri [URI]") do |uri|
    config.api_uri = uri
  end

  options.on("-U", "--user [USER]") do |user|
    config.login_user = user
  end

  options.on("-P", "--password [PASSWORD]") do |pass|
    config.login_pass = pass
  end

  options.on("-n", "--num-hosts [NUM HOSTS]") do |num|
    config.dummy_host_count = num.to_i
  end

  options.parse!(ARGV)
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
    @num_hosts = @config.dummy_host_count
    super(@config.api_uri)
    login(@config.login_user, @config.login_pass)
  end

  def setup
    cleanup

    puts "Register dummy hosts ..."

    @num_hosts.times do |i|
      host_name = "TestHost#{i}"
      create_host(host_name)
    end
  end

  def cleanup
    puts "Remove all dummy hosts ..."

    @num_hosts.times do |i|
      host_name = "TestHost#{i}"
      delete_host(host_name)
    end
  end

  def run
    p "run"
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

  def get_template_id(name = "Template OS Linux")
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

  def get_group_id(name = "Linux servers")
    params = {
      "filter" => {
        "name" => name,
      },
    }
    groups = hostgroup.get(params)
    groups[0]["groupid"]
  end

  def delete_host(host_name)
    host_id = get_host_id(host_name)
    return unless host_id

    delete_params =
      [
       {
         "hostid" => host_id,
       },
      ]
    host.delete(delete_params)
  end

  def create_host(host_name, group_id = nil, template_id = nil)
    group_id = get_group_id unless group_id
    template_name = default_linux_template_name
    template_id = get_template_id(template_name) unless template_id

    ip_address = "127.0.0.1"
    port = 10050

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

    iface_params = get_iface_params(ip_address, port)
    create_params = base_params.merge(iface_params)

    host.create(create_params)

    p create_params
  end

  def run_all
    setup
    run
    cleanup
  end

  private
  def default_linux_template_name
    case self.API_version
    when "1.2", "1.3"
      "Template_Linux"
    else
      "Template OS Linux"
    end
  end

  def get_iface_params(ip_address, port)
    case self.API_version
    when "1.2", "1.3"
      {
        "ip" => ip_address,
        "port" => port,
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
           "ip" => ip_address,
           "dns" => "",
           "port" => port,
         },
        ],
      }
    end
  end
end


begin
  benchmark = Benchmark.new
  command = ARGV[0]
  if command
    benchmark.send(command)
  else
    benchmark.run_all
  end
rescue ZbxAPI_ExceptionLoginPermission => e
  p e.error_code
  p e.message
  e.show_backtrace
end
