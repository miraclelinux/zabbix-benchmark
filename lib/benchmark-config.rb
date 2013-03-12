require 'singleton'
require 'yaml'
require 'yaml/store'
require 'fileutils'

class BenchmarkConfig
  include Singleton

  attr_accessor :uri, :login_user, :login_pass, :max_retry_count
  attr_accessor :num_hosts, :hosts_step, :shuffle_hosts
  attr_accessor :host_group, :template_name, :custom_agents
  attr_accessor :warmup_duration, :measurement_duration
  attr_accessor :clear_db_on_every_step
  attr_accessor :write_throughput_result_file, :config_output_path, :histories
  attr_accessor :zabbix_log_file, :zabbix_log_directory, :rotate_zabbix_log
  attr_accessor :read_latency_log_file, :read_latency_result_file 
  attr_accessor :read_throughput_log_file, :read_throughput_result_file 
  attr_accessor :read_latency_try_count, :read_throughput_threads
  attr_accessor :reading_data_begin_time, :reading_data_end_time
  attr_accessor :reading_data_hosts, :reading_data_fill_time
  attr_accessor :history_duration_for_reading_throughput
  attr_accessor :history_duration_for_reading_latency
  attr_accessor :default_command
  attr_accessor :read_latency, :read_throughput

  SECONDS_IN_HOUR = 60 * 60
  ITEM_UPDATE_INTERVAL = 5

  def initialize
    @uri = "http://localhost/zabbix/"
    @login_user = "Admin"
    @login_pass = "zabbix"
    @max_retry_count = 2
    @num_hosts = 10
    @hosts_step = 0
    @shuffle_hosts = false
    @host_group = "Linux servers"
    @template_name = "Template_Linux_5sec"
    @custom_agents = []
    @default_agents = 
      [
       { "ip_address" => "127.0.0.1", "port" => 10050 },
      ]
    @zabbix_log_file = "/tmp/zabbix_server.log"
    @zabbix_log_directory = "output/log"
    @read_latency_log_file = "output/log/read-latency.log"
    @read_throughput_log_file = "output/log/read-throughput.log"
    @rotate_zabbix_log = false
    @write_throughput_result_file = "output/result-write-throughput.csv"
    @read_throughput_result_file = "output/result-read-throughput.csv"
    @read_latency_result_file = "output/result-read-latency.csv"
    @config_output_path = "output/config.yml"
    @histories = []
    @warmup_duration = 60
    @measurement_duration = 60
    @clear_db_on_every_step = false
    @read_latency_try_count = 10
    @read_throughput_threads = 10
    @reading_data_begin_time = nil
    @reading_data_end_time = nil
    @reading_data_hosts = 40
    @reading_data_fill_time = SECONDS_IN_HOUR
    @history_duration_for_reading_throughput = 60 * 10
    @history_duration_for_reading_latency = ITEM_UPDATE_INTERVAL * 2
    @default_command = "run"

    @read_latency = {
      "history_duration" => ITEM_UPDATE_INTERVAL * 2,
      "result_file"      => "output/result-read-latency.csv",
      "log_file"         => "output/log/read-latency.log",
    }
    @read_throughput = {
      "history_duration" => 60 * 10,
      "num_threads"      => 10,
      "result_file"      => "output/result-read-throughput.csv",
      "log_file"         => "output/log/read-throughput.log",
    }
  end

  def load_file(path)
    file = YAML.load_file(path)
    file.each do |key, value|
      self.send("#{key}=", value)
    end
  end

  def export(path = nil)
    path ||= @config_output_path

    FileUtils.mkdir_p(File.dirname(path))

    db = YAML::Store.new(path)
    db.transaction do
      config_variables.each do |variable|
        key = variable.delete("@")
        db[key] = instance_variable_get(variable)
      end
    end
  end

  def agents
    if @custom_agents.empty?
      @default_agents
    else
      @custom_agents
    end
  end

  def agents=(agents)
    @custom_agents = agents
  end

  def step
    if @hosts_step > 0 and @hosts_step < @num_hosts
      @hosts_step
    else
      @num_hosts
    end
  end

  def reset
    initialize
    self
  end

  private
  def config_variables
    ignore_variables = ["@config_output_path", "@default_agents"]
    variables = instance_variables - ignore_variables
    variables.sort
  end
end
