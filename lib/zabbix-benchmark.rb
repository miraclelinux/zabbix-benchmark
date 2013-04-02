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

class ZabbixBenchmark
  MODE_WRITING = 0
  MODE_READING = 1

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
    @mysql = nil
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

  def reading_benchmark
    @zabbix.ensure_loggedin

    @benchmark_mode = MODE_READING

    conf = @config.history_data
    if conf["begin_time"] and conf["end_time"]
      @reading_data_begin_time = Time.parse(conf["begin_time"])
      @reading_data_end_time = Time.parse(conf["end_time"])
      puts("Time range of reading benchmark data:")
      puts("  Begin: #{conf["begin_time"]}")
      puts("  End  : #{conf["end_time"]}")
      puts
    else
      setup_benchmark_data
    end

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
      setup_next_level if writing_mode? or running
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
    @config.histories.each do |config|
      FileUtils.rm_rf(config["path"])
    end
  end

  def cleanup_all_hosts
    @zabbix.ensure_loggedin
    puts("Remove all dummy hosts ...")

    hosts = @zabbix.get_registered_test_hosts(@config.host_group)
    hosts.each do |host_params|
      puts("Remove #{host_params["host"]}")
      ensure_api_call do
        @zabbix.delete_host(host_params["hostid"].to_i)
      end
    end
  end

  def test_history
    @zabbix.ensure_loggedin
    duration = @config.read_throughput["history_duration"]
    end_time = Time.now
    begin_time = end_time - duration
    collect_zabbix_histories(begin_time, end_time)
  end

  # FIXME: will be replaced with "fill_history"
  def setup_benchmark_data
    enable_n_hosts(@config.history_data["num_hosts"])
    @reading_data_begin_time = Time.now
    puts "Begin time: #{@reading_data_begin_time}"
    sleep(@config.history_data["fill_time"])
    @reading_data_end_time = Time.now
    puts "End time  : #{@reading_data_end_time}"
    disable_all_hosts
  end

  def fill_history_hgl
    fill_history
  end

  def fill_history_mysql
    require 'mysql2'
    @mysql = Mysql2::Client.new(:host => "localhost",
                                :username => "zabbix",
                                :password => "zabbix",
                                :database => "zabbix")
    fill_history
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

    ensure_api_call do
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
    collect_zabbix_histories
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
        ensure_api_call do
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
    @zabbix.get_history(item, begin_time, end_time)
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
        ensure_api_call(10) do
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

  def collect_zabbix_histories(begin_time = nil, end_time = nil)
    @config.histories.each do |config|
      ensure_api_call do
        collect_zabbix_history(config["host"], config["key"], config["path"],
                               begin_time, end_time)
      end
    end
  end

  def collect_zabbix_history(host, key, path, begin_time = nil, end_time = nil)
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
      ensure_api_call do
        if (enable)
          @zabbix.enable_hosts(hosts_slice)
        else
          @zabbix.disable_hosts(hosts_slice)
        end
      end
    end
  end

  def writing_mode?
    @benchmark_mode == MODE_WRITING
  end

  def reading_mode?
    @benchmark_mode == MODE_READING
  end

  def setup_dummy_history_for_item_by_hgl(item)
    conf = @config.history_data
    itemid = item["itemid"].to_i
    begin_time = Time.parse(conf["begin_time"])
    end_time = Time.parse(conf["end_time"])

    case item["value_type"].to_i
    when ZbxAPIUtils::VALUE_TYPE_INTEGER
      command = "add_uint"
      interval = conf["interval"]
    when ZbxAPIUtils::VALUE_TYPE_FLOAT
      command = "add_float"
      interval = conf["interval"]
    when ZbxAPIUtils::VALUE_TYPE_STRING
      command = "add_string"
      interval = conf["interval_string"]
    else
      puts("Error: unknown data type: #{item["value_type"]}")
      return
    end

    program_path = "./tools/hgl-setup-dummy-data"
    args = [itemid, begin_time.to_i, end_time.to_i, interval]
    `#{program_path} #{command} zabbix #{args.join(" ")}`

    unless $?.success?
      puts("Failed to call #{program_path}")
    end
  end

  def table_and_value_for_type(value_type)
    case value_type
    when ZbxAPIUtils::VALUE_TYPE_INTEGER
      ['history_uint', '1']
    when ZbxAPIUtils::VALUE_TYPE_STRING
      ['history_str', '"dummy"']
    else
      ['history', '1.0']
    end
  end

  def sql_query_for_one_day(table, item, clock_offset)
    itemid = item["itemid"].to_i
    last_clock = clock_offset + 60 * 60 * 24 - 600
    table, value = table_and_value_for_type(item["value_type"].to_i)
    query = "INSERT INTO #{table} (itemid, clock, ns, value) VALUES "
    clock_offset.step(last_clock, 600) do |clock|
      query += "(#{itemid}, #{clock}, 0, #{value})"
      query += ", " if clock < last_clock
    end
    query += ";"
    query
  end

  def setup_dummy_history_for_item_by_sql(item)
    conf = @config.history_data
    begin_time = Time.parse(conf["begin_time"])
    end_time = Time.parse(conf["end_time"])
    step = 60 * 60 * 24

    begin_time.to_i.step(end_time.to_i, step) do |clock_offset|
      query = sql_query_for_one_day("history", item, clock_offset);
      @mysql.query(query)
    end
  end

  def fill_history
    @zabbix.ensure_loggedin

    conf = @config.history_data
    @hostnames.slice(0, conf["num_hosts"]).each_with_index do |hostname, i|
      items = @zabbix.get_items(hostname)
      items.each_with_index do |item, j|
        puts("hosts: #{i + 1}/#{conf["num_hosts"]}, items: #{j + 1}/#{items.length}")
        if @mysql
          setup_dummy_history_for_item_by_sql(item)
        else
          setup_dummy_history_for_item_by_hgl(item)
        end
      end
    end
  end
end
