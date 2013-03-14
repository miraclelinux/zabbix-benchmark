$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require "test/unit/rr"
require 'zabbix-benchmark-test-util'
require 'zabbix-benchmark'

class ZabbixBenchmarkChild <  ZabbixBenchmark
  attr_accessor :zabbix
end

class ZabbixBenchmarkTestCase < Test::Unit::TestCase
  include ZabbixBenchmarkTestUtil

  def setup
    @zabbix = ZbxAPIUtils.new("http://test-host/", "Admin", "zabbix")
    stub(@zabbix).ensure_loggedin
    stub(@zabbix).API_version { "1.4\n" }
    @benchmark = benchmark
  end

  def teardown
    BenchmarkConfig.instance.reset
  end

  def benchmark
    benchmark = ZabbixBenchmarkChild.new
    benchmark.zabbix = @zabbix
    benchmark
  end

  def test_api_version
    str = capture do
      @benchmark.api_version
    end
    assert_equal("1.4\n", str)
  end

  def test_enable_12_hosts
    BenchmarkConfig.instance.num_hosts = 20
    mock(@zabbix).enable_hosts(10.times.collect { |i| ("TestHost#{i}") }).once
    mock(@zabbix).enable_hosts(2.times.collect { |i| ("TestHost1#{i}") }).once
    output = capture do
      benchmark.enable_n_hosts("12")
    end
    assert_equal("Enable 12 dummy hosts ...\n", output)
  end

  def test_enable_all_hosts
    BenchmarkConfig.instance.num_hosts = 41
    mock(@zabbix).enable_hosts(10.times.collect { |i| ("TestHost#{i}") }).once
    mock(@zabbix).enable_hosts(10.times.collect { |i| ("TestHost1#{i}") }).once
    mock(@zabbix).enable_hosts(10.times.collect { |i| ("TestHost2#{i}") }).once
    mock(@zabbix).enable_hosts(10.times.collect { |i| ("TestHost3#{i}") }).once
    mock(@zabbix).enable_hosts(["TestHost40"]).once
    output = capture do
      benchmark.enable_all_hosts
    end
    assert_equal("Enable all dummy hosts ...\n", output)
  end

  data("3 hosts" => ["token-3hosts.txt", 3],
       "4 hosts" => ["token-4hosts.txt", 4])

  def test_print_cassandra_token(data)
    expected, n_hosts = data
    BenchmarkConfig.instance.num_hosts = 10
    hostnames = 10.times.collect { |i| ("TestHost#{i}") }
    mock(@zabbix).get_items_range(hostnames) { [72373, 72984] }.once
    output = capture do
      benchmark.print_cassandra_token(n_hosts)
    end
    expected = File.read(fixture_file_path(expected))
    assert_equal(expected, output)
  end
end
