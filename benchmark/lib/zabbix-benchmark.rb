$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'fileutils'
require 'zbxapi'
require 'benchmark-config'
require 'zabbix-log'

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

class Benchmark
  MONITORED_HOST = "0"
  UNMONITORED_HOST = "1"

  def initialize
    @config = BenchmarkConfig.instance
    @initial_hosts = 0
    @initial_items = 0
    @last_status = {
      :begin_time => nil,
      :end_time => nil,
      :level => -1
    }
    @n_items_in_template = nil
    @zabbix = ZabbixAPI.new(@config.uri)
  end

  def test_connection
    ensure_loggedin
    puts "succeeded to connect to #{@config.uri}"
  end

  def test_history
    ensure_loggedin
    seconds_in_hour = 60 * 60
    @last_status[:begin_time] = Time.now - seconds_in_hour
    @last_status[:end_time] = Time.now
    collect_zabbix_histories
  end

  def api_version
    ensure_loggedin
    puts "#{@zabbix.API_version}"
  end

  def setup
    ensure_loggedin
    cleanup
    get_initial_state
    setup_next_level
  end

  def cleanup_output_files
    FileUtils.rm_rf(@config.data_file_path)
    @config.histories.each do |config|
      FileUtils.rm_rf(config["path"])
    end
  end

  def cleanup_hosts
    ensure_loggedin
    puts "Remove all dummy hosts ..."

    groupid = get_group_id(@config.host_group)
    params = {
      "output" => "extend",
      "groupids" => [groupid],
    }
    hosts = @zabbix.host.get(params)

    hosts.each do |host_params|
      if host_params["host"] =~ /\ATestHost\d+\Z/
        puts "Remove #{host_params["host"]}"
        delete_host(host_params["hostid"].to_i)
      end
    end
  end

  def cleanup
    cleanup_output_files
    cleanup_hosts
  end

  def run
    ensure_loggedin
    cleanup
    get_initial_state
    rotate_zabbix_log
    until is_last_level do
      setup_next_level
      warmup
      collect_data
      rotate_zabbix_log
    end
    cleanup_hosts
  end

  private
  def ensure_loggedin
    unless @zabbix.loggedin?
      @zabbix.login(@config.login_user, @config.login_pass)
    end
  end

  def level_head
    level = @last_status[:level]
    @config.step * level
  end

  def level_tail
    tail = level_head + @config.step - 1
    tail < @config.num_hosts ? tail : @config.num_hosts
  end

  def n_hosts
    level_tail + 1
  end

  def n_hosts_to_add
    level_tail - level_head + 1
  end

  def n_items_in_template
    unless @n_items_in_template
      id = get_template_id(template_name)
      items = @zabbix.item.get({"templateids" => [id]})
      @n_items_in_template = items.length
    end
    @n_items_in_template
  end

  def n_items
    n_items_in_template * n_hosts
  end

  def total_rec_hosts
    n_hosts + @initial_hosts
  end

  def total_rec_items
    n_items + @initial_items
  end

  def is_last_level
    level_tail + 1 >= @config.num_hosts
  end

  def get_initial_state
    ensure_loggedin
    params = {
      "filter" => { "status" => MONITORED_HOST },
      "output" => "extend",
    }
    hosts = @zabbix.host.get(params)
    @initial_hosts = hosts.length

    hosts.each do |host|
      item_params = {
        "host" => host["host"],
        "output" => "shorten",
      }
      items = @zabbix.item.get(item_params)
      @initial_items += items.length
    end
  end

  def setup_next_level
    @last_status[:level] += 1

    puts "Register #{n_hosts_to_add} dummy hosts ..."

    level_head.upto(level_tail) do |i|
      host_name = "TestHost#{i}"
      agent = @config.agents[i % @config.agents.length]
      create_host(host_name, agent)
    end

    puts ""

    @last_status[:begin_time] = Time.now
  end

  def warmup
    duration = @config.warmup_duration
    print "warmup #{duration} seconds ...\n\n"
    sleep duration
    @last_status[:end_time] = Time.now
  end

  def collect_data
    print "collect_data\n"
    collect_dbsync_time
    collect_zabbix_histories
  end

  def rotate_zabbix_log
    return unless @config.rotate_zabbix_log

    src = @config.zabbix_log_file
    dest = "#{@config.zabbix_log_file}.#{n_hosts}"
    begin
      FileUtils.mv(src, dest)
    rescue
      STDERR.puts("Warning: Failed to rotate zabbix log. " +
                  "Please check the permission.")
    end
  end

  def collect_dbsync_time
    log = ZabbixLog.new(@config.zabbix_log_file)
    log.set_time_range(@last_status[:begin_time], @last_status[:end_time])
    log.parse
    average, n_written_items = log.history_sync_average

    FileUtils.mkdir_p(File.dirname(@config.data_file_path))
    open(@config.data_file_path, "a") do |file|
      file << "#{total_rec_hosts},#{total_rec_items},#{average},#{n_written_items}\n"
    end

    print_dbsync_time(average, n_written_items)
  end

  def collect_zabbix_histories
    @config.histories.each do |config|
      collect_zabbix_history(config["host"], config["key"], config["path"])
    end
  end

  def collect_zabbix_history(host, key, path)
    ensure_loggedin

    history = get_history(host, key)
    return unless history

    FileUtils.mkdir_p(File.dirname(path))
    open(path, "a") do |file|
      history.each do |item|
        file << "#{total_rec_hosts},#{total_rec_items},#{item["clock"]},#{item["value"]}\n"
      end
    end
  end

  def get_items(host, key)
    item_params = {
      "host" => host,
      "filter" => { "key_" => key },
      "output" => "shorten",
    }
    @zabbix.item.get(item_params)
  end

  def get_history(host, key)
    items = get_items(host, key)
    return nil if items.empty?

    item_id = items[0]["itemid"]
    history_params = {
      "history" => 0,
      "itemids" => [item_id],
      "time_from" => @last_status[:begin_time].to_i,
      "time_till" => @last_status[:end_time].to_i,
      "output" => "extend",
    }
    @zabbix.history.get(history_params)
  end

  def print_dbsync_time(average, n_written_items)
    print "hosts: #{total_rec_hosts}\n"
    print "dbsync average: #{average} [msec/item]\n"
    print "total #{n_written_items} items are written\n\n"
  end

  def get_host_id(name)
    params = {
      "filter" => { "host" => name },
    }
    hosts = @zabbix.host.get(params)
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
    templates = @zabbix.template.get(params)
    case @zabbix.API_version
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
    groups = @zabbix.hostgroup.get(params)
    groups[0]["groupid"]
  end

  def create_host(host_name, agent = nil)
    agent ||= @config.agents[0]

    group_name = @config.host_group
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
    }
    host_params = base_params.merge(iface_params(agent))

    @zabbix.host.create(host_params)

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
    @zabbix.host.delete(delete_params)
  end

  def template_name
    if @config.template_name
      @config.template_name
    else
      default_linux_template_name
    end
  end

  def default_linux_template_name
    case @zabbix.API_version
    when "1.2", "1.3"
      "Template_Linux"
    else
      "Template OS Linux"
    end
  end

  def iface_params(agent)
    case @zabbix.API_version
    when "1.2", "1.3"
      {
        "ip" => agent["ip_address"],
        "port" => agent["port"],
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
           "ip" => agent["ip_address"],
           "dns" => "",
           "port" => agent["port"],
         },
        ],
      }
    end
  end
end
