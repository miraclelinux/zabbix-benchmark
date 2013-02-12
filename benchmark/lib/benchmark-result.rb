require 'fileutils'
require 'benchmark-config'

class WriteThroughputResult
  def initialize(config)
    @config = config
    @path = @config.write_throughput_result_file
    @has_header = false
    @result_rows = []
  end

  def add(row)
    output_headers unless @has_header
    @result_rows << row
    output_row(row)
  end

  private
  def output_headers
    FileUtils.mkdir_p(File.dirname(@path))
    open(@path, "a") do |file|
      file << "Begin time, End time,"
      file << "Enabled hosts,Enabled items,"
      file << "Average processing time [msec/history],"
      file << "Written histories,Total processing time [sec],"
      file << "Read histories,Total read time [sec],"
      file << "Agent errors\n"
    end
    @has_header = true
  end

  def time_to_zabbix_format(time)
    '%s.%03d' % [time.strftime("%Y%m%d:%H%M%S"), (time.usec / 1000)]
  end

  def output_row(row)
    FileUtils.mkdir_p(File.dirname(@path))
    open(@path, "a") do |file|
      begin_time = time_to_zabbix_format(row[:begin_time])
      end_time = time_to_zabbix_format(row[:end_time])
      file << "#{begin_time},#{end_time},"
      file << "#{row[:n_enabled_hosts]},#{row[:n_enabled_items]},"
      file << "#{row[:average]},"
      file << "#{row[:n_written_items]},#{row[:total_time]},"
      file << "#{row[:n_read_items]},#{row[:total_read_time]},"
      file << "#{row[:n_agent_errors]}\n"
    end
  end
end

class ReadLatencyResult
  attr_accessor :path

  def initialize(config)
    @config = config
    @path = @config.read_latency_result_file
    @header = nil
    @result_rows = []
  end

  def add(row)
    output_headers unless @header
    @result_rows << row
    output_row(row)
  end

  private
  def output_headers
    @header = "Enabled hosts,Enabled items,Read latency [sec]\n"
    FileUtils.mkdir_p(File.dirname(@path))
    open(@path, "a") do |file|
      file.write(@header)
    end
  end

  def output_row(row)
    FileUtils.mkdir_p(File.dirname(@path))
    open(@path, "a") do |file|
      file << "#{row[:n_enabled_hosts]},#{row[:n_enabled_items]},"
      file << "#{row[:read_latency]}\n"
    end
  end
end
