require 'singleton'
require 'yaml'

class BenchmarkConfig
  include Singleton

  attr_accessor :uri, :login_user, :login_pass
  attr_accessor :num_hosts, :hosts_step
  attr_accessor :host_group, :template_name, :custom_agents
  attr_accessor :warmup_duration, :measurement_duration, :data_file_path
  attr_accessor :zabbix_log_file, :rotate_zabbix_log
  attr_accessor :histories
  attr_accessor :retry_count

  def initialize
    @uri = "http://localhost/zabbix/"
    @login_user = "Admin"
    @login_pass = "zabbix"
    @num_hosts = 10
    @hosts_step = 0
    @host_group = "Linux servers"
    @template_name = nil
    @custom_agents = []
    @default_agents = 
      [
       { "ip_address" => "127.0.0.1", "port" => 10050 },
      ]
    @zabbix_log_file = "/var/log/zabbix/zabbix_server.log"
    @rotate_zabbix_log = false
    @data_file_path = "output/dbsync-average.dat"
    @warmup_duration = 60
    @measurement_duration = 60
    @histories = []
    @retry_count = 2
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
