require 'singleton'
require 'yaml'

class BenchmarkConfig
  include Singleton

  attr_accessor :uri, :login_user, :login_pass, :retry_count
  attr_accessor :num_hosts, :hosts_step, :shuffle_hosts
  attr_accessor :host_group, :template_name, :custom_agents
  attr_accessor :warmup_duration, :measurement_duration
  attr_accessor :data_file_path, :histories
  attr_accessor :zabbix_log_file, :zabbix_log_directory, :rotate_zabbix_log
  attr_accessor :fill_time

  SECONDS_IN_HOUR = 60 * 60

  def initialize
    @uri = "http://localhost/zabbix/"
    @login_user = "Admin"
    @login_pass = "zabbix"
    @retry_count = 2
    @num_hosts = 10
    @hosts_step = 0
    @shuffle_hosts = false
    @host_group = "Linux servers"
    @template_name = nil
    @custom_agents = []
    @default_agents = 
      [
       { "ip_address" => "127.0.0.1", "port" => 10050 },
      ]
    @zabbix_log_file = "/tmp/zabbix_server.log"
    @zabbix_log_directory = "output/log"
    @rotate_zabbix_log = false
    @data_file_path = "output/dbsync-average.dat"
    @histories = []
    @warmup_duration = 60
    @measurement_duration = 60
    @fill_time = SECONDS_IN_HOUR
  end

  def load_file(path)
    file = YAML.load_file(path)
    file.each do |key, value|
      self.send("#{key}=", value)
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
end
