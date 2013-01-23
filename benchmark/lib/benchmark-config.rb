require 'singleton'
require 'yaml'
require 'yaml/store'

class BenchmarkConfig
  include Singleton

  attr_accessor :uri, :login_user, :login_pass, :retry_count
  attr_accessor :num_hosts, :hosts_step, :shuffle_hosts
  attr_accessor :host_group, :template_name, :custom_agents
  attr_accessor :warmup_duration, :measurement_duration
  attr_accessor :clear_db_on_every_step
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
    @config_backup_file = "output/config.yml"
    @histories = []
    @warmup_duration = 60
    @measurement_duration = 60
    @clear_db_on_every_step = false
    @fill_time = SECONDS_IN_HOUR
  end

  def load_file(path)
    file = YAML.load_file(path)
    file.each do |key, value|
      self.send("#{key}=", value)
    end
  end

  def export_setting(path = nil)
    path ||= @config_backup_file
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
    variables = instance_variables
    ignore_variables = ["@config_backup_file", "@default_agents"]
    ignore_variables.each do |variable|
      variables.delete(variable)
    end
    variables.sort
  end
end
