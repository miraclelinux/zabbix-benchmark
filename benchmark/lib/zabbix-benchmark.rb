$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'fileutils'
require 'zbxapi'
require 'benchmark-config'
require 'zabbix-log'
require 'zbxapi-utils'

class ZabbixBenchmark
  def initialize
    @config = BenchmarkConfig.instance
    @hostnames = @config.num_hosts.times.collect { |i| "TestHost#{i}" }
    @hostnames.shuffle! if @config.shuffle_hosts
    @remaining_hostnames = @hostnames.each_slice(@config.step).to_a
    @processed_hostnames = []
    @last_status = {
      :begin_time => nil,
      :end_time => nil,
    }
    @n_enabled_hosts = 0
    @n_enabled_items = 0
    @zabbix = ZbxAPIUtils.new(@config.uri, @config.login_user, @config.login_pass)
    @zabbix_log = ZabbixLog.new(@config.zabbix_log_file)
    @zabbix_log.set_rotation_directory(@config.zabbix_log_directory)
  end

  def api_version
    @zabbix.ensure_loggedin
    puts "#{@zabbix.API_version}"
  end

  def setup(status = nil)
    status ||= ZbxAPIUtils::UNMONITORED_HOST

    @zabbix.ensure_loggedin

    cleanup_all_hosts

    puts "Register #{@config.num_hosts} dummy hosts ..."
    @config.num_hosts.times do |i|
      host_name = "TestHost#{i}"
      agent = @config.agents[i % @config.agents.length]
      ensure_api_call do
        @zabbix.create_host(host_name, @config.host_group,
                            @config.template_name, agent, status)
      end
    end
  end

  def run
    @zabbix.ensure_loggedin
    setup
    run_without_setup
    cleanup_all_hosts
  end

  def run_without_setup
    @zabbix.ensure_loggedin
    cleanup_output_files
    @config.export
    rotate_zabbix_log
    output_csv_column_titles
    until @remaining_hostnames.empty? do
      setup_next_level
      warmup
      measure_write_performance
      measure_read_performance
      rotate_zabbix_log
    end
    disable_all_hosts
  end

  def cleanup
    cleanup_output_files
    cleanup_all_hosts
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
    @zabbix.ensure_loggedin
    puts "Remove all dummy hosts ..."

    groupid = @zabbix.get_group_id(@config.host_group)
    params = {
      "output" => "extend",
      "groupids" => [groupid],
    }
    hosts = @zabbix.host.get(params)

    hosts.each do |host_params|
      if host_params["host"] =~ /\ATestHost\d+\Z/
        puts "Remove #{host_params["host"]}"
        ensure_api_call do
          @zabbix.delete_host(host_params["hostid"].to_i)
        end
      end
    end
  end

  def test_history
    @zabbix.ensure_loggedin
    seconds_in_hour = 60 * 60
    @last_status[:begin_time] = Time.now - seconds_in_hour
    @last_status[:end_time] = Time.now
    collect_zabbix_histories
  end

  def fill_history
    setup

    print("sleep #{@config.fill_time} seconds ...\n")
    sleep @config.fill_time

    cleanup_all_hosts
  end

  def print_cassandra_token(n_nodes = nil)
    n_nodes = n_nodes ? n_nodes.to_i : 3

    min, max = @zabbix.get_items_range(@hostnames)
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

  private
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

  def update_enabled_hosts_and_items
    @zabbix.ensure_loggedin
    params = {
      "filter" => { "status" => ZbxAPIUtils::MONITORED_HOST },
      "output" => "extend",
    }
    hosts = @zabbix.host.get(params)
    @n_enabled_hosts = hosts.length

    hostids = hosts.collect { |host| host["hostid"] }
    item_params = {
      "filter" => { "status" => ZbxAPIUtils::ENABLED_ITEMS },
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
        @zabbix.enable_hosts(hosts_slice)
      end
    end

    ensure_api_call do
      update_enabled_hosts_and_items
    end

    @processed_hostnames << hostnames

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
    puts "warmup #{duration} seconds ..."
    sleep duration
  end

  def measure_write_performance
    if not @config.enable_writing_benchmark
      puts "Writing benchmark is disabled! Skip it."
      return
    end

    duration = @config.measurement_duration
    puts "measuring write performance for #{duration} seconds ..."
    @last_status[:begin_time] = Time.now
    sleep duration
    @last_status[:end_time] = Time.now

    print "collecting results ...\n\n"
    collect_write_log
    collect_zabbix_histories
  end

  def measure_read_performance
    if not @config.enable_reading_benchmark
      #puts "Reading benchmark is disabled! Skip it."
      return
    end

    puts "measuring read performance ..."
    puts "currently under development, skit it"
    puts ""
  end

  def get_random_enabled_item
    hostnames = @processed_hostnames[rand(@processed_hostnames.length)]
    hostname = hostnames[rand(hostnames.length)]
    items = @zabbix.get_items(hostname)
    items[rand(items.length)]
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
    @zabbix.ensure_loggedin

    history = @zabbix.get_history_by_key(host, key,
                                         @last_status[:begin_time],
                                         @last_status[:end_time])
    return unless history

    FileUtils.mkdir_p(File.dirname(path))
    open(path, "a") do |file|
      history.each do |item|
        file << "#{@n_enabled_hosts},#{@n_enabled_items},"
        file << "#{item["clock"]},#{item["value"]}\n"
      end
    end
  end

  def print_write_performance(average, n_written_items)
    print "enabled hosts: #{@n_enabled_hosts}\n"
    print "enabled items: #{@n_enabled_items}\n"
    print "dbsync average: #{average} [msec/item]\n"
    print "total #{n_written_items} items are written\n\n"
  end

  def disable_all_hosts
    @zabbix.ensure_loggedin

    puts "Disable all dummy hosts ..."

    # Zabbix returns error when it receives hundreds of host ids
    hosts_slices = @hostnames.each_slice(10).to_a
    hosts_slices.each do |hosts_slice|
      ensure_api_call do
        @zabbix.disable_hosts(hosts_slice)
      end
    end
  end
end
