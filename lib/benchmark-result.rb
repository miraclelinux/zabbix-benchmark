$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'fileutils'
require 'csv'
require 'benchmark-config'

class BenchmarkResults
  attr_accessor :write_throughput
  attr_accessor :read_throughput, :read_throughput_log
  attr_accessor :read_latency, :read_latency_log

  def initialize(config)
    @config = config
    @write_throughput      = WriteThroughputResult.new(@config)
    @read_throughput       = ReadThroughputResult.new(@config)
    @read_throughput_log   = ReadThroughputLog.new(@config)
    @read_latency          = ReadLatencyResult.new(@config)
    @read_latency_log      = ReadLatencyLog.new(@config)
  end

  def cleanup
    FileUtils.rm_rf(@config.write_throughput_result_file)
    FileUtils.rm_rf(@config.read_throughput_result_file)
    FileUtils.rm_rf(@config.read_throughput_log_file)
    FileUtils.rm_rf(@config.read_latency_result_file)
    FileUtils.rm_rf(@config.read_latency_log_file)
  end
end

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

  def load(path = nil)
    path ||= @path
    header = nil
    CSV.open(path, "r") do |row|
      if header.nil?
        header = row
      else
        @rows.push(row)
      end
    end
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

class ReadLatencyLog < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.read_latency_log_file
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
      ]
  end

  def analyze_statistics_one_step(rows)
    total = 0
    rows.each do |row|
      total += row[2].to_f
    end
    average = total / rows.length

    variance = 0
    rows.each do |row|
      variance += (row[2].to_f - average) ** 2
    end

    standard_deviation = Math.sqrt(variance / rows.length)

    puts("#{rows[0][0].to_i}, #{rows.length}, #{average}, #{variance}, #{standard_deviation}")
  end

  def analyze_statistics
    current_items = nil
    rows = []
    @rows.each do |row|
      items = row[1].to_i

      if current_items and items != current_items
        analyze_statistics_one_step(rows)
        current_items = items
        rows = [row]
      else
        rows.push(row)
      end

      current_items = items if !current_items
    end

    analyze_statistics_one_step(rows)
  end
end

class ReadLatencyResult < ReadLatencyLog
  def initialize(config)
    super(config)
    @path = @config.read_latency_result_file
    @columns +=
      [
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
         :label => :time,
         :title => "Time"
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
