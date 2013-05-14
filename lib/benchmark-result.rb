$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'fileutils'
require 'csv'
require 'benchmark-config'

class BenchmarkResults
  attr_reader :write_throughput
  attr_reader :read_throughput, :read_throughput_log
  attr_reader :read_latency, :read_latency_log
  attr_reader :error_log

  def initialize(config)
    @config = config
    @files = []
    @files.push(@write_throughput    = WriteThroughputResult.new(@config))
    @files.push(@read_throughput     = ReadThroughputResult.new(@config))
    @files.push(@read_throughput_log = ReadThroughputLog.new(@config))
    @files.push(@read_latency        = ReadLatencyResult.new(@config))
    @files.push(@read_latency_log    = ReadLatencyLog.new(@config))
    @files.push(@error_log           = ErrorLog.new(@config))
  end

  def cleanup
    @files.each do |file|
      file.cleanup
    end
  end
end

class BenchmarkResult
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
    @rows.clear
    @has_header = false
    if CSV.respond_to?(:foreach)
      CSV.foreach(path) { |row| push_row(row) }
    else
      CSV.open(path, "r") { |row| push_row(row) }
    end
  end

  def cleanup
    FileUtils.rm_rf(@path) if @path
  end

  def each_legend(legend_column)
    rows_in_legend = []

    @rows.each_with_index do |row, i|
      rows_in_legend.push(row)
      next_row = @rows[i + 1]
      legend = row[legend_column].to_i
      next_legend = next_row ? next_row[legend_column].to_i : -1
      if next_legend != legend
        yield(legend, rows_in_legend)
        rows_in_legend = []
      end
    end
  end

  private
  def output_header
    output_row
    @has_header = true
  end

  def output_row(row = nil)
    open(@path, "a") do |file|
      values = []
      @columns.each do |column|
        if row
          value = row[column[:label]]
          value = time_to_zabbix_format(value) if value.kind_of?(Time)
        else
          value = column[:title]
        end
        values << value
      end
      file << "#{values.join(',')}\n"
    end
  end

  def push_row(row)
    if @has_header
      @rows.push(row)
    else
      @has_header = true
    end
  end

  def time_to_zabbix_format(time)
    '%s.%03d' % [time.strftime("%Y%m%d:%H%M%S"), (time.usec / 1000)]
  end
end

class ErrorLog < BenchmarkResult
  def initialize(config)
    super(config)
    @path = @config.error_log_file
    @columns =
      [
       {
         :label => :time,
         :title => "Time"
       },
       {
         :label => :message,
         :title => "message"
       },
      ]
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
  N_HOSTS_COLUMN = 0
  N_ITEMS_COLUMN = 1

  def initialize(config)
    super(config)
    @path = @config.read_latency["log_file"]
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
         :label => :history_duration,
         :title => "History duration"
       },
       {
         :label => :read_latency,
         :title => "Read latency [sec]"
       },
      ]
  end

  def analyze_statistics
    statistics = []
    each_legend(N_ITEMS_COLUMN) do |legend, rows|
      statistics.push(analyze_statistics_one_step(rows))
    end
    statistics
  end

  def output_statistics
    statistics = analyze_statistics
    print("Enabled hosts,Enabled items,Length,Min,Max,Mean,")
    puts("Variance,Standard deviation,Confidence min,Confidence max")
    float_value_keys = [:min, :max, :mean,
                        :variance, :standard_deviation,
                        :confidence_min, :confidence_max]
    statistics.each do |row|
      print("#{row[:n_hosts]},#{row[:n_items]},#{row[:length]}")
      float_value_keys.each do |key|
        print(",%.4e" % row[key])
      end
      puts
    end
  end

  private
  def analyze_statistics_one_step(rows)
    value_column = 2
    values = rows.collect { |row| row[value_column].to_f }
    total = values.inject(0) { |sum, value| sum += value}
    mean = total / rows.length
    variance = values.inject(0) do |sum, value|
      sum += (value - mean) ** 2
    end
    variance /= rows.length
    standard_deviation = Math.sqrt(variance)

    {
      :n_hosts            => rows[0][N_HOSTS_COLUMN].to_i,
      :n_items            => rows[0][N_ITEMS_COLUMN].to_i,
      :length             => rows.length,
      :total              => total,
      :min                => values.min,
      :max                => values.max,
      :mean               => mean,
      :variance           => variance,
      :standard_deviation => standard_deviation,
      :confidence_min     => mean - standard_deviation * 2,
      :confidence_max     => mean + standard_deviation * 2,
    }
  end
end

class ReadLatencyResult < ReadLatencyLog
  def initialize(config)
    super(config)
    @path = @config.read_latency["result_file"]
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
    @path = @config.read_throughput["log_file"]
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
         :label => :history_duration,
         :title => "History duration"
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
    @path = @config.read_throughput["result_file"]
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
         :label => :history_duration,
         :title => "History duration"
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
