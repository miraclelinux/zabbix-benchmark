$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require 'zabbix-benchmark-test-util'
require 'benchmark-result'

class BenchmarkResultTestCase < Test::Unit::TestCase
  include ZabbixBenchmarkTestUtil

  def setup
    @config = BenchmarkConfig.instance.reset
  end

  def teardown
    @config.reset
  end

  def test_read_latency_statistics
    @config.read_latency["log_file"] = fixture_file_path("read-latency.log")
    read_latency_log = ReadLatencyLog.new(@config)
    read_latency_log.load
    expected = File.read(fixture_file_path("read-latency-statistics.csv"))
    actual = capture do
      read_latency_log.output_statistics
    end
    assert_equal(expected, actual)
  end
end

