$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'fileutils'
require 'benchmark'
require 'zbxapi'
require 'benchmark-config'
require 'benchmark-result'
require 'zabbix-log'
require 'zbxapi-utils'

class ZabbixBenchmark
  ITEM_UPDATE_INTERVAL = 5

  def initialize
    @config = BenchmarkConfig.instance
    @hostnames = @config.num_hosts.times.collect { |i| "TestHost#{i}" }
    @hostnames.shuffle! if @config.shuffle_hosts
    @remaining_hostnames = @hostnames.each_slice(@config.step).to_a
    @processed_hostnames = []
    @last_status = {
      :begin_time => nil,
      :end_time   => nil,
    }
    @n_enabled_hosts = 0
    @n_enabled_items = 0
    @zabbix = ZbxAPIUtils.new(@config.uri, @config.login_user, @config.login_pass)
    @zabbix_log = ZabbixLog.new(@config.zabbix_log_file)
    @zabbix_log.set_rotation_directory(@config.zabbix_log_directory)
    @write_throughput_result = WriteThroughputResult.new(@config)
    @read_latency_result = ReadLatencyResult.new(@config)
    @read_latency_log = ReadLatencyResult.new(@config)
    @read_latency_log.path = @config.read_latency_log_file
    @read_throughput_result = ReadThroughputResult.new(@config)
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
    FileUtils.rm_rf(@config.write_throughput_result_file)
    FileUtils.rm_rf(@config.read_latency_result_file)
    FileUtils.rm_rf(@config.read_throughput_result_file)
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
      "output"   => "extend",
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

  def enable_all_hosts
    puts "Enable all dummy hosts ..."
    enable_hosts(@hostnames, true)
  end

  def disable_all_hosts
    puts "Disable all dummy hosts ..."
    enable_hosts(@hostnames, false)
  end

  private
  def ensure_api_call(max_retry_count = nil)
    max_retry_count ||= @config.max_retry_count
    retry_count = 0
    begin
      yield
    rescue StandardError, Timeout::Error
      if retry_count < max_retry_count
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
      "filter"  => { "status" => ZbxAPIUtils::ENABLED_ITEMS },
      "hostids" => hostids,
      "output"  => "shorten",
    }
    items = @zabbix.item.get(item_params)
    @n_enabled_items = items.length
  end

  def setup_next_level
    hostnames = @remaining_hostnames.shift

    puts "Enable #{hostnames.length} dummy hosts: "
    p hostnames

    enable_hosts(hostnames)

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
      puts "Reading benchmark is disabled! Skip it."
      return
    end

    measure_read_latency_average
    measure_read_throughput
  end

  def measure_read_throughput
    total_count = 0
    total_lock = Mutex.new
    n_threads = 10
    threads = []
    end_time = Time.now + @config.measurement_duration

    n_threads.times do |i|
      threads[i] = Thread.new do
        count = measure_read_throughput_thread(end_time)
        total_lock.synchronize do
          total_count += count
        end
      end
    end

    n_threads.times do |i|
      threads[i].join
    end

    throughput_data = {
      :n_enabled_hosts => @n_enabled_hosts,
      :n_enabled_items => @n_enabled_items,
      :read_histories  => total_count,
    }
    @read_throughput_result.add(throughput_data)

    print("Total read histories: #{total_count}\n")
  end

  def measure_read_throughput_thread(end_time)
    count = 0
    while Time.now < end_time do
      hostid = @zabbix.get_host_id(random_enabled_hostname)
      histories = get_histories_for_host(hostid)
      count += histories.length
    end
    count
  end

  def get_histories_for_host(hostid)
    end_time = Time.now
    seconds_in_hour = 60 * 60
    begin_time = end_time - seconds_in_hour
    value_types = ZbxAPIUtils::SUPPORTED_VALUE_TYPES
    history_params = {
      "history"   => value_types[rand(value_types.length)],
      "hostids"   => [hostid],
      "time_from" => begin_time.to_i,
      "time_till" => end_time.to_i,
      "output"    => "extend",
    }
    @zabbix.history.get(history_params)
  end

  def measure_read_latency_average
    total_time = 0
    total_count = 0

    10.times do
      time = nil
      ensure_api_call do
        time = measure_read_latency
      end
      total_time += time
      total_count += 1
    end

    average_time = total_time / total_count
    latency_data = {
      :n_enabled_hosts => @n_enabled_hosts,
      :n_enabled_items => @n_enabled_items,
      :read_latency    => average_time,
    }
    @read_latency_result.add(latency_data)

    average_time
  end

  def measure_read_latency(item = nil)
    item ||= random_enabled_item
    histories = []
    end_time = Time.now
    begin_time = end_time - ITEM_UPDATE_INTERVAL * 2
    elapsed = Benchmark.measure do
      histories = @zabbix.get_history(item, begin_time, end_time)
    end
    raise "No History" if histories.empty?

    latency_data = {
      :n_enabled_hosts => @n_enabled_hosts,
      :n_enabled_items => @n_enabled_items,
      :read_latency    => elapsed.real,
    }
    @read_latency_log.add(latency_data)

    elapsed.real
  end

  def random_enabled_hostname
    hostnames = @processed_hostnames[rand(@processed_hostnames.length)]
    hostnames[rand(hostnames.length)]
  end

  def random_enabled_item
    items = @zabbix.get_items(random_enabled_hostname)
    items[rand(items.length)]
  end

  def rotate_zabbix_log
    @zabbix_log.rotate(@n_enabled_hosts.to_s) if @config.rotate_zabbix_log
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

    throughput_data = {
      :begin_time      => @last_status[:begin_time],
      :end_time        => @last_status[:end_time],
      :n_enabled_hosts => @n_enabled_hosts,
      :n_enabled_items => @n_enabled_items,
      :average         => average,
      :n_written_items => n_written_items,
      :total_time      => total_time,
      :n_read_items    => n_read_items,
      :total_read_time => total_read_time,
      :n_agent_errors  => n_agent_errors,
    }
    @write_throughput_result.add(throughput_data)

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

  def enable_hosts(hostnames = nil, enable = true)
    @zabbix.ensure_loggedin

    # Zabbix returns error when it receives hundreds of host ids
    hosts_slices = hostnames.each_slice(10).to_a
    hosts_slices.each do |hosts_slice|
      ensure_api_call do
        if (enable)
          @zabbix.enable_hosts(hosts_slice)
        else
          @zabbix.disable_hosts(hosts_slice)
        end
      end
    end
  end
end
