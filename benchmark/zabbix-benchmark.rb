#!/usr/bin/env ruby
require 'rubygems'
require 'zbxapi'

class Benchmark < ZabbixAPI
  def initialize
    @server_url="http://localhost:8080/zabbix/"
    @login_user="admin"
    @login_pass="admin"
    @num_hosts = 10
    super(@server_url)
    login(@login_user, @login_pass)
  end

  def setup
    cleanup
    @num_hosts.times do |i|
      host_name = "TestHost#{i}"
      create_host(host_name)
    end
  end

  def cleanup
    @num_hosts.times do |i|
      host_name = "TestHost#{i}"
      delete_host(host_name)
    end
  end

  def run
    p "run"
  end

  def show_info
    p loggedin?
    p self.API_version
  end

  def get_host_id(name = "Zabbix Server")
    params = {
      :filter => { :host => name },
    }
    hosts = host.get(params)
    if hosts.empty?
      nil
    else
      hosts[0]["hostid"]
    end
  end

  def get_template_id(name = "Template_Linux")
    params = {
      :filter => { :host => name, },
    }
    templates = template.get(params)
    templates.keys[0]
  end

  def get_group_id(name = "Zabbix Servers")
    params = {
      :filter => {
        :name => name,
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
         :hostid => host_id,
       },
      ]
    host.delete(delete_params)
  end

  def create_host(host_name, group_id = nil, template_id = nil)
    group_id = get_group_id unless group_id
    template_id = get_template_id unless template_id

    ip_address = "127.0.0.1"
    port = 10050

    create_params = {
      :host => host_name,

      :groups =>
      [
       { :groupid => group_id },
      ],
      :templates =>
      [
       { :templateid => template_id },
      ],

      # Zabbix 2.0
      :interfaces =>
      [
       {
         :type => 1,
         :main => 1,
         :useip => 1,
         :ip => ip_address,
         :dns => "",
         :port => port,
       },
      ],

      # Zabbix 1.8
      :ip => ip_address,
      :port => port,
      :useip => 1,
      :dns => "",
    }
    host.create(create_params)
  end
end


begin
  benchmark = Benchmark.new
  benchmark.setup
  benchmark.run
  benchmark.cleanup
rescue ZbxAPI_ExceptionLoginPermission => e
  p e.error_code
  p e.message
  e.show_backtrace
end
