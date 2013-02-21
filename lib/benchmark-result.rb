require 'fileutils'
require 'benchmark-config'

class BenchmarkResult
  attr_accessor :path

  def initialize(config)
    @config = config
    @path = nil
    @has_header = false
    @columns = []
    @rows = []
  end

  def add(row)
    @rows << row
    FileUtils.mkdir_p(File.dirname(@path))
    output_header unless @has_header
    output_row(row)
  end

  private
  def output_header
    return if @has_header
    output_row
    @has_header = true
  end

  def output_row(row = nil)
    open(@path, "a") do |file|
      line = ""
      @columns.each do |column|
        if row
          value = row[column[:label]]
          value = time_to_zabbix_format(value) if value.kind_of?(Time)
        else
          value = column[:title]
        end
        line += "," unless line.empty?
        line += "#{value}"
      end
      line += "\n"
      file << line
    end
  end

  def time_to_zabbix_format(time)
    '%s.%03d' % [time.strftime("%Y%m%d:%H%M%S"), (time.usec / 1000)]
  end
end

class WriteThroughputResult < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.write_throughput_result_file
    @columns =
      [
       {
         :label => :begin_time,
         :title => "Begin time"
       },
       {
         :label => :end_time,
         :title => "End time"
       },
       {
         :label => :n_enabled_hosts,
         :title => "Enabled hosts"
       },
       {
         :label => :n_enabled_items,
         :title => "Enabled items"
       },
       {
         :label => :dbsync_average,
         :title => "Average processing time [msec/history]"
       },
       {
         :label => :n_written_items,
         :title => "Written histories"
       },
       {
         :label => :total_time,
         :title => "Total processing time [sec]"
       },
       {
         :label => :n_read_items,
         :title => "Read histories"
       },
       {
         :label => :total_read_time,
         :title => "Total read time [sec]"
       },
       {
         :label => :n_agent_errors,
         :title => "Agent errors"
       },
      ]
  end
end

class ReadLatencyResult < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.read_latency_result_file
    @columns = 
      [
       {
         :label => :n_enabled_hosts,
         :title => "Enabled hosts"
       },
       {
         :label => :n_enabled_items,
         :title => "Enabled items"
       },
       {
         :label => :read_latency,
         :title => "Read latency [sec]"
       },
       {
         :label => :success_count,
         :title => "Success count"
       },
       {
         :label => :error_count,
         :title => "Error count"
       },
      ]
  end
end

class ReadThroughputLog < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.read_throughput_log_file
    @columns =
      [
       {
         :label => :n_enabled_hosts,
         :title => "Enabled hosts"
       },
       {
         :label => :n_enabled_items,
         :title => "Enabled items"
       },
       {
         :label => :thread,
         :title => "Thread"
       },
       {
         :label => :processed_items,
         :title => "Processed items"
       },
       {
         :label => :processed_time,
         :title => "Processed time"
       },
      ]
  end
end

class ReadThroughputResult < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.read_throughput_result_file
    @columns = 
      [
       {
         :label => :n_enabled_hosts,
         :title => "Enabled hosts"
       },
       {
         :label => :n_enabled_items,
         :title => "Enabled items"
       },
       {
         :label => :read_histories,
         :title => "Read histories"
       },
       {
         :label => :read_time,
         :title => "Total read time"
       },
       {
         :label => :written_histories,
         :title => "Written histories"
       },
      ]
  end
end
