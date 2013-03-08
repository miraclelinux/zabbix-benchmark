require 'rubygems'
require 'test-unit'
require 'zabbix-benchmark-test-util'
require '../lib/benchmark-result.rb'

class BenchmarkResultTestCase < Test::Unit::TestCase
  include ZabbixBenchmarkTestUtil

  def setup
    @config = BenchmarkConfig.instance.reset
  end

  def teardown
    @config.reset
  end

  def test_read_latency_statistics
    read_latency_log = ReadLatencyLog.new(@config)
    read_latency_log.path = fixture_file_path("read-latency.log")
    read_latency_log.load
    expected = File.read(fixture_file_path("read-latency-statistics.csv"))
    actual = capture do
      read_latency_log.output_statistics
    end
    assert_equal(expected, actual)
  end
end

