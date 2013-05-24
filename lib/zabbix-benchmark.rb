$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'fileutils'
require 'time'
require 'benchmark'
require 'zbxapi'
require 'benchmark-config'
require 'benchmark-result'
require 'zabbix-log'
require 'zbxapi-utils'
require 'history-database'

class ZabbixBenchmark
  MODE_WRITING = 0
  MODE_READING = 1

  def self.show_commands
    commands = self.public_instance_methods(false)
    help_string = commands.sort.join("\n  ")
    puts "Available commands:"
    puts "  #{help_string}"
  end

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
    @zabbix = ZbxAPIUtils.new(@config.uri,
                              @config.login_user,
                              @config.login_pass)
    @zabbix_log = ZabbixLog.new(@config.zabbix_log_file)
    @zabbix_log.set_rotation_directory(@config.zabbix_log_directory)
    @benchmark_mode = MODE_WRITING
    @results = BenchmarkResults.new(@config)
    @history_db = nil
  end

  def api_version
    @zabbix.ensure_loggedin
    puts("#{@zabbix.API_version}")
  end

  def setup(status = nil)
    status ||= ZbxAPIUtils::UNMONITORED_HOST

    @zabbix.ensure_loggedin

    cleanup_all_hosts

    puts("Register #{@config.num_hosts} dummy hosts ...")
    @config.num_hosts.times do |i|
      host_name = "TestHost#{i}"
      agent = @config.agents[i % @config.agents.length]
      ensure_call do
        @zabbix.create_host(host_name, @config.host_group,
                            @config.template_name, agent, status)
      end
    end
  end

  def writing_benchmark
    run_without_setup
  end

  def reading_benchmark(backend_name = nil)
    @zabbix.ensure_loggedin

    @benchmark_mode = MODE_READING

    if HistoryDatabase.known_db?(backend_name)
      @history_db = HistoryDatabase.create(@config, backend_name)
    end

    conf = @config.history_data
    @reading_data_begin_time = Time.parse(conf["begin_time"])
    @reading_data_end_time = Time.parse(conf["end_time"])
    puts("Time range of reading benchmark data:")
    puts("  Begin: #{conf["begin_time"]}")
    puts("  End  : #{conf["end_time"]}")
    puts

    run_without_setup
  end

  def run_without_setup
    @zabbix.ensure_loggedin
    cleanup_output_files
    @config.export
    rotate_zabbix_log
    disable_all_hosts(true)
    running = false
    until running and @remaining_hostnames.empty?
      if writing_mode? or running
        setup_next_level
      else
        update_enabled_hosts_and_items
      end
      running = true
      print_current_level_conditions
      warmup
      measure
      rotate_zabbix_log
      puts
    end
    disable_all_hosts
  end

  def cleanup
    cleanup_output_files
    cleanup_all_hosts
  end

  def cleanup_output_files
    FileUtils.rm_rf(@config.config_output_path)
    FileUtils.rm_rf(@config.zabbix_log_directory)
    @results.cleanup
    @config.self_monitoring_items.each do |config|
      FileUtils.rm_rf(config["path"])
    end
  end

  def cleanup_all_hosts
    @zabbix.ensure_loggedin
    puts("Remove all dummy hosts ...")

    hosts = @zabbix.get_registered_test_hosts(@config.host_group)
    hosts.each do |host_params|
      puts("Remove #{host_params["host"]}")
      ensure_call do
        @zabbix.delete_host(host_params["hostid"].to_i)
      end
    end
  end

  def test_self_monitoring
    @zabbix.ensure_loggedin
    duration = BenchmarkConfig::SECONDS_IN_HOUR
    end_time = Time.now
    begin_time = end_time - duration
    collect_self_monitoring_items(begin_time, end_time)
  end

  def fill_history(backend_name = nil)
    @history_db = HistoryDatabase.create(@config, backend_name)
    process_history_data_for_item do |item|
      @history_db.setup_histories(item)
    end
  end

  def clear_history(backend_name = nil)
    @history_db = HistoryDatabase.create(@config, backend_name)
    process_history_data_for_item do |item|
      @history_db.cleanup_histories(item)
    end
  end

  def print_cassandra_token(n_nodes = nil)
    n_nodes = n_nodes ? n_nodes.to_i : 3

    min, max = @zabbix.get_items_range(@hostnames)
    diff = max - min

    puts("min itemid: #{min}")
    puts("max itemid: #{max}")
    puts

    1.upto(n_nodes) do |i|
      value = min + (diff * i / n_nodes)
      value = max + 1 if i == n_nodes
      key_string = sprintf("%016x%08x%08x", value, value, 0, 0)
      hex_code = key_string.unpack("H*")[0]
      puts("Node #{i}:")
      puts("  max itemid: #{value}")
      puts("  key string: #{key_string}")
      puts("  hex code: #{hex_code}")
      puts
    end
  end

  def enable_n_hosts(hosts_count)
    puts("Enable #{hosts_count} dummy hosts ...")
    enable_hosts(@hostnames[0, hosts_count.to_i], true)
  end

  def enable_all_hosts
    puts("Enable all dummy hosts ...")
    enable_hosts(@hostnames, true)
  end

  def disable_all_hosts(check = false)
    hosts = @zabbix.get_enabled_test_hosts if check
    if not check or not hosts.empty?
      puts("Disable all dummy hosts ...")
      enable_hosts(@hostnames, false)
    end
  end

  def read_latency_statistics(path = nil)
    log = ReadLatencyLog.new(BenchmarkConfig.instance)
    log.load(path)
    log.output_statistics
  end

  private
  def ensure_call(max_retry_count = nil)
    max_retry_count ||= @config.max_retry_count
    retry_count = 0
    begin
      yield
    rescue StandardError, Timeout::Error => error
      entry = {
        :time    => Time.now,
        :message => error.inspect,
      }
      @results.error_log.add(entry)

      if retry_count < max_retry_count
        retry_count += 1
        retry
      else
        raise
      end
    end
  end

  def update_enabled_hosts_and_items
    hosts = @zabbix.get_enabled_hosts
    @n_enabled_hosts = hosts.length

    hostids = hosts.collect { |host| host["hostid"] }
    items = @zabbix.get_enabled_items(hostids)
    @n_enabled_items = items.length
  end

  def setup_next_level
    return if @remaining_hostnames.empty?

    hostnames = @remaining_hostnames.shift
    puts("Enable #{hostnames.length} dummy hosts: ")
    p hostnames

    enable_hosts(hostnames)

    ensure_call do
      update_enabled_hosts_and_items
    end

    @processed_hostnames << hostnames

    clear_history_db if @config.clear_db_on_every_step
  end

  def clear_history_db
    print("Clear DB...")
    output = `history-gluon-cli delete zabbix 2>&1`
    if $?.success?
      puts("done.")
    else
      puts("Failed to call history-gluon-cli!")
      puts("#{output}")
    end
  end

  def warmup
    duration = @config.warmup_duration
    puts("Warmup #{duration} seconds ...")
    sleep duration
  end

  def measure
    case @benchmark_mode
    when MODE_READING
      measure_read_performance
    when MODE_WRITING
      measure_write_performance
    end
  end

  def measure_write_performance
    duration = @config.measurement_duration
    puts("Measuring write performance for #{duration} seconds ...")
    @last_status[:begin_time] = Time.now
    sleep duration
    @last_status[:end_time] = Time.now

    puts("Collecting results ...")
    throughput_data = collect_write_log
    @results.write_throughput.add(throughput_data)
    print_write_performance(throughput_data)
    collect_self_monitoring_items
  end

  def measure_read_performance
    range = @config.history_duration_for_read
    range["min"].step(range["max"], range["step"]) do |duration|
      puts "History duration: #{duration}"
      measure_read_latency_average(duration)
      measure_read_throughput(duration)
      puts
    end
  end

  def measure_read_throughput(history_duration)
    total_processed_items = 0
    total_processed_time = 0
    log = []
    total_lock = Mutex.new
    threads = []
    begin_time = Time.now
    end_time = begin_time + @config.measurement_duration

    @config.read_throughput["num_threads"].times do |i|
      threads[i] = Thread.new do
        result = measure_read_throughput_thread(i, end_time, history_duration)
        total_lock.synchronize do
          total_processed_items += result[:total_processed_items]
          total_processed_time += result[:total_processed_time]
          log += result[:log]
        end
      end
    end
    threads.each { |thread| thread.join }

    write_throughput = collect_write_log(begin_time, end_time)
    read_throughput = {
      :n_enabled_hosts   => @n_enabled_hosts,
      :n_enabled_items   => @n_enabled_items,
      :history_duration  => history_duration,
      :read_histories    => total_processed_items,
      :read_time         => total_processed_time,
      :written_histories => write_throughput[:n_written_items],
    }
    @results.read_throughput.add(read_throughput)
    @results.write_throughput.add(write_throughput)

    log.sort { |a, b| a[:time] <=> b[:time] }.each do |entry|
      @results.read_throughput_log.add(entry)
    end

    puts("Total read histories: #{total_processed_items}")
  end

  def measure_read_throughput_thread(thread_id, end_time, history_duration)
    result = {
      :total_processed_items => 0,
      :total_processed_time  => 0,
      :log                   => [],
    }
    while Time.now < end_time do
      histories = []
      begin
        ensure_call do
          elapsed = Benchmark.measure do
            if @config.read_throughput["history_group"] == "host"
              histories = get_random_host_histories(history_duration)
            else
              histories = get_random_item_histories(history_duration)
            end
          end
          result[:total_processed_items] += histories.length
          result[:total_processed_time]  += elapsed.real
          result[:log] << {
            :time             => Time.now,
            :n_enabled_hosts  => @n_enabled_hosts,
            :n_enabled_items  => @n_enabled_items,
            :history_duration => history_duration,
            :thread           => thread_id,
            :processed_items  => histories.length,
            :processed_time   => elapsed.real,
          }
        end
      rescue StandardError, Timeout::Error
      end
    end
    result
  end

  def random_time_range(history_duration)
    diff = @reading_data_end_time.to_i - @reading_data_begin_time.to_i
    begin_time = @reading_data_begin_time + rand(diff - history_duration)
    end_time = begin_time + history_duration
    [begin_time, end_time]
  end

  def get_histories_for_item(item, history_duration)
    begin_time, end_time = random_time_range(history_duration)
    if @history_db
      @history_db.get_histories(item, begin_time, end_time)
    else
      @zabbix.get_history(item, begin_time, end_time)
    end
  end

  def get_histories_for_hostid(hostid, history_duration)
    begin_time, end_time = random_time_range(history_duration)
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

  def get_random_item_histories(history_duration)
    get_histories_for_item(random_enabled_item, history_duration)
  end

  def get_random_host_histories(history_duration)
    hostid = @zabbix.get_host_id(random_enabled_hostname)
    get_histories_for_hostid(hostid, history_duration)
  end

  def measure_read_latency_average(history_duration)
    average_time = 0
    total_time = 0
    success_count = 0
    error_count = 0

    @config.read_latency["try_count"].times do
      time = nil
      begin
        ensure_call(10) do
          time = measure_read_latency(history_duration)
        end
        total_time += time
        success_count += 1
      rescue StandardError, Timeout::Error
        error_count += 1
      end
    end

    average_time = total_time / success_count if success_count > 0
    latency_data = {
      :n_enabled_hosts  => @n_enabled_hosts,
      :n_enabled_items  => @n_enabled_items,
      :history_duration => history_duration,
      :read_latency     => average_time,
      :success_count    => success_count,
      :error_count      => error_count,
    }
    @results.read_latency.add(latency_data)

    puts("Average read latency: #{average_time}")

    average_time
  end

  def measure_read_latency(history_duration)
    item = random_enabled_item
    histories = []
    elapsed = Benchmark.measure do
      histories = get_histories_for_item(item, history_duration)
    end
    raise "No History" if histories.empty?

    latency_data = {
      :n_enabled_hosts  => @n_enabled_hosts,
      :n_enabled_items  => @n_enabled_items,
      :history_duration => history_duration,
      :read_latency     => elapsed.real,
    }
    @results.read_latency_log.add(latency_data)

    elapsed.real
  end

  def random_enabled_hostname
    @hostnames[rand(@config.history_data["num_hosts"])]
  end

  def random_enabled_item
    items = @zabbix.get_items(random_enabled_hostname)
    items[rand(items.length)]
  end

  def rotate_zabbix_log
    @zabbix_log.rotate(@n_enabled_hosts.to_s) if @config.rotate_zabbix_log
  end

  def collect_write_log(begin_time = nil, end_time = nil)
    begin_time ||= @last_status[:begin_time]
    end_time ||= @last_status[:end_time]

    begin
      @zabbix_log.parse(begin_time, end_time)
      average, n_written_items, total_time = @zabbix_log.dbsyncer_total
      n_read_items, total_read_time = @zabbix_log.poller_total
      n_agent_errors = @zabbix_log.n_agent_errors
    rescue
      STDERR.puts("Warning: Failed to read zabbix log!")
    end

    {
      :begin_time      => begin_time,
      :end_time        => end_time,
      :n_enabled_hosts => @n_enabled_hosts,
      :n_enabled_items => @n_enabled_items,
      :dbsync_average  => average,
      :n_written_items => n_written_items,
      :total_time      => total_time,
      :n_read_items    => n_read_items,
      :total_read_time => total_read_time,
      :n_agent_errors  => n_agent_errors,
    }
  end

  def collect_self_monitoring_items(begin_time = nil, end_time = nil)
    @config.self_monitoring_items.each do |config|
      ensure_call do
        collect_self_monitoring_item(config["host"],
                                     config["key"], config["path"],
                                     begin_time, end_time)
      end
    end
  end

  def collect_self_monitoring_item(host, key, path, begin_time = nil, end_time = nil)
    begin_time ||= @last_status[:begin_time]
    end_time ||= @last_status[:end_time]

    @zabbix.ensure_loggedin

    history = @zabbix.get_history_by_key(host, key, begin_time, end_time)
    return unless history

    FileUtils.mkdir_p(File.dirname(path))
    open(path, "a") do |file|
      history.each do |item|
        file << "#{@n_enabled_hosts},#{@n_enabled_items},"
        file << "#{item["clock"]},#{item["value"]}\n"
      end
    end
  end

  def print_current_level_conditions
    puts
    puts("Enabled hosts: #{@n_enabled_hosts}")
    puts("Enabled items: #{@n_enabled_items}")
    puts
  end

  def print_write_performance(write_throughput)
    puts("DBsync average: #{write_throughput[:dbsync_average]} [msec/item]")
    puts("Total #{write_throughput[:n_written_items]} items are written")
  end

  def enable_hosts(hostnames = nil, enable = true)
    @zabbix.ensure_loggedin

    # Since Zabbix frontend returns error when it receives hundreds of host ids,
    # we don't process all hosts at once.
    hosts_slices = hostnames.each_slice(10).to_a
    hosts_slices.each do |hosts_slice|
      ensure_call do
        if (enable)
          @zabbix.enable_hosts(hosts_slice)
        else
          @zabbix.disable_hosts(hosts_slice)
        end
      end
    end
  end

  def process_history_data_for_item
    @zabbix.ensure_loggedin

    conf = @config.history_data
    @hostnames.slice(0, conf["num_hosts"]).each_with_index do |hostname, i|
      items = @zabbix.get_items(hostname)
      items.each_with_index do |item, j|
        puts("hosts: #{i + 1}/#{conf["num_hosts"]}, items: #{j + 1}/#{items.length}")
        yield(item)
      end
    end
  end

  def writing_mode?
    @benchmark_mode == MODE_WRITING
  end

  def reading_mode?
    @benchmark_mode == MODE_READING
  end
end
