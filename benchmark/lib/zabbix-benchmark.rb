$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'fileutils'
require 'zbxapi'
require 'benchmark-config'
require 'zabbix-log'
require 'zbxapi-utils'

class Benchmark
  MONITORED_HOST = "0"
  UNMONITORED_HOST = "1"
  ENABLED_ITEMS = "0"
  DISABLED_ITEMS = "1"

  def initialize
    @config = BenchmarkConfig.instance
    @hostnames = @config.num_hosts.times.collect { |i| "TestHost#{i}" }
    @hostnames.shuffle! if @config.shuffle_hosts
    @remaining_hostnames = @hostnames.each_slice(@config.step).to_a
    @last_status = {
      :begin_time => nil,
      :end_time => nil,
    }
    @n_enabled_hosts = 0
    @n_enabled_items = 0
    @zabbix = ZabbixAPI.new(@config.uri)
    @zabbix_log = ZabbixLog.new(@config.zabbix_log_file)
    @zabbix_log.set_rotation_directory(@config.zabbix_log_directory)
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

  def cleanup_output_files
    FileUtils.rm_rf(@config.data_file_path)
    FileUtils.rm_rf(@config.config_output_path)
    FileUtils.rm_rf(@config.zabbix_log_directory)
    @config.histories.each do |config|
      FileUtils.rm_rf(config["path"])
    end
  end

  def cleanup_all_hosts
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
        ensure_api_call do
          delete_host(host_params["hostid"].to_i)
        end
      end
    end
  end

  def cleanup
    cleanup_output_files
    cleanup_all_hosts
  end

  def run
    ensure_loggedin
    setup
    run_without_setup
    cleanup_all_hosts
  end

  def run_without_setup
    ensure_loggedin
    cleanup_output_files
    @config.export
    rotate_zabbix_log
    output_csv_column_titles
    until @remaining_hostnames.empty? do
      setup_next_level
      warmup
      measure_write_performance
      rotate_zabbix_log
    end
    disable_all_hosts
  end

  def setup(status = nil)
    status ||= UNMONITORED_HOST

    ensure_loggedin

    cleanup_all_hosts

    puts "Register #{@config.num_hosts} dummy hosts ..."
    @config.num_hosts.times do |i|
      host_name = "TestHost#{i}"
      agent = @config.agents[i % @config.agents.length]
      ensure_api_call do
        create_host(host_name, agent, status)
      end
    end
  end

  def print_cassandra_token(n_nodes = nil)
    n_nodes = n_nodes ? n_nodes.to_i : 3

    min, max = get_items_range
    diff = max - min

    puts("min itemid: #{min}")
    puts("max itemid: #{max}")
    puts("")

    1.upto(n_nodes) do |i|
      value = min + (diff * i / n_nodes)
      value = max + 1 if i == n_nodes
      key_string = sprintf("%016x%08x%08x", value, value, 0, 0)
      hex_code = key_string.unpack("H*")[0]
      puts("Node #{i}:")
      puts("  max itemid: #{value}")
      puts("  key string: #{key_string}")
      puts("  hex code: #{hex_code}")
      puts("")
    end
  end

  def fill_history
    setup

    print("sleep #{@config.fill_time} seconds ...\n")
    sleep @config.fill_time

    cleanup_all_hosts
  end

  private
  def ensure_loggedin
    unless @zabbix.loggedin?
      @zabbix.login(@config.login_user, @config.login_pass)
    end
  end

  def update_enabled_hosts_and_items
    ensure_loggedin
    params = {
      "filter" => { "status" => MONITORED_HOST },
      "output" => "extend",
    }
    hosts = @zabbix.host.get(params)
    @n_enabled_hosts = hosts.length

    hostids = hosts.collect { |host| host["hostid"] }
    item_params = {
      "filter" => { "status" => ENABLED_ITEMS },
      "hostids" => hostids,
      "output" => "shorten",
    }
    items = @zabbix.item.get(item_params)
    @n_enabled_items = items.length
  end

  def setup_next_level
    hostnames = @remaining_hostnames.shift

    puts "Enable #{hostnames.length} dummy hosts: "
    p hostnames

    # Zabbix returns error when it receives hundreds of host ids
    hosts_slices = hostnames.each_slice(10).to_a
    hosts_slices.each do |hosts_slice|
      ensure_api_call do
        enable_hosts(hosts_slice)
      end
    end

    clear_history_db if @config.clear_db_on_every_step

    puts ""
  end

  def clear_history_db
    print("Clear DB...")
    output = `history-gluon-cli delete zabbix 2>&1`
    if $?.success?
      puts("done.")
    else
      puts("failed to call history-gluon-cli!")
      puts("#{output}")
    end
  end

  def warmup
    duration = @config.warmup_duration
    print "warmup #{duration} seconds ...\n\n"
    sleep duration
  end

  def measure_write_performance
    duration = @config.measurement_duration
    print "measuring #{duration} seconds ...\n\n"
    @last_status[:begin_time] = Time.now
    sleep duration
    @last_status[:end_time] = Time.now

    print "collect_data\n"
    ensure_api_call do
      update_enabled_hosts_and_items
    end
    collect_write_log
    collect_zabbix_histories
  end

  def rotate_zabbix_log
    @zabbix_log.rotate(@n_enabled_hosts.to_s) if @config.rotate_zabbix_log
  end

  def output_csv_column_titles
    FileUtils.mkdir_p(File.dirname(@config.data_file_path))
    open(@config.data_file_path, "a") do |file|
      file << "Begin time, End time,"
      file << "Enabled hosts,Enabled items,"
      file << "Average processing time [msec/history],"
      file << "Written histories,Total processing time [sec],"
      file << "Read histories,Total read time [sec],"
      file << "Agent errors\n"
    end
  end

  def time_to_zabbix_format(time)
    time.strftime("%Y%m%d:%H%M%S.000")
  end

  def collect_write_log
    begin
      @zabbix_log.parse(@last_status[:begin_time], @last_status[:end_time])
      average, n_written_items, total_time = @zabbix_log.dbsyncer_total
      n_read_items, total_read_time = @zabbix_log.poller_total
      n_agent_errors = @zabbix_log.n_agent_errors
    rescue
      STDERR.puts("Warning: Failed to read zabbix log!")
    end

    FileUtils.mkdir_p(File.dirname(@config.data_file_path))
    open(@config.data_file_path, "a") do |file|
      begin_time = time_to_zabbix_format(@last_status[:begin_time])
      end_time = time_to_zabbix_format(@last_status[:end_time])
      file << "#{begin_time},#{end_time},"
      file << "#{@n_enabled_hosts},#{@n_enabled_items},"
      file << "#{average},"
      file << "#{n_written_items},#{total_time},"
      file << "#{n_read_items},#{total_read_time},"
      file << "#{n_agent_errors}\n"
    end

    print_write_performance(average, n_written_items)
  end

  def collect_zabbix_histories
    @config.histories.each do |config|
      ensure_api_call do
        collect_zabbix_history(config["host"], config["key"], config["path"])
      end
    end
  end

  def collect_zabbix_history(host, key, path)
    ensure_loggedin

    history = get_history(host, key)
    return unless history

    FileUtils.mkdir_p(File.dirname(path))
    open(path, "a") do |file|
      history.each do |item|
        file << "#{@n_enabled_hosts},#{@n_enabled_items},"
        file << "#{item["clock"]},#{item["value"]}\n"
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
    value_type = items[0]["value_type"]
    history_params = {
      "history" => value_type,
      "itemids" => [item_id],
      "time_from" => @last_status[:begin_time].to_i,
      "time_till" => @last_status[:end_time].to_i,
      "output" => "extend",
    }
    @zabbix.history.get(history_params)
  end

  def print_write_performance(average, n_written_items)
    print "enabled hosts: #{@n_enabled_hosts}\n"
    print "enabled items: #{@n_enabled_items}\n"
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
    templates[0]["templateid"]
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

  def ensure_api_call
    max_retry ||= @config.retry_count
    retry_count = 0
    begin
      yield
    rescue StandardError, Timeout::Error
      if retry_count < max_retry
        retry_count += 1
        retry
      else
        raise
      end
    end
  end

  def create_host(host_name, agent = nil, status = nil)
    agent ||= @config.agents[0]
    status ||= MONITORED_HOST

    group_name = @config.host_group
    group_id = get_group_id(group_name)
    template_id = get_template_id(@config.template_name)

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

  def disable_all_hosts
    ensure_loggedin

    puts "Disable all dummy hosts ..."

    # Zabbix returns error when it receives hundreds of host ids
    hosts_slices = @hostnames.each_slice(10).to_a
    hosts_slices.each do |hosts_slice|
      ensure_api_call do
        disable_hosts(hosts_slice)
      end
    end
  end

  def get_host_ids(hostnames)
    ensure_loggedin
    params = {
      "filter" => { "host" => hostnames },
    }
    @zabbix.host.get(params)
  end

  def set_host_statuses(hostnames, status)
    ensure_loggedin
    params = {
      "hosts" => get_host_ids(hostnames),
      "status" => status,
    }
    @zabbix.host.massUpdate(params)
  end

  def enable_hosts(hostnames)
    set_host_statuses(hostnames, MONITORED_HOST)
  end

  def disable_hosts(hostnames)
    set_host_statuses(hostnames, UNMONITORED_HOST)
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

  def get_items_range
    host_ids = get_host_ids(@hostnames)
    host_ids = host_ids.collect { |id| id["hostid"] }
    item_params = {
      "hostids" => host_ids,
      "output" => "shorten",
    }
    items = @zabbix.item.get(item_params)
    item_ids = items.collect { |item| item["itemid"].to_i }

    [item_ids.min, item_ids.max]
  end
end
