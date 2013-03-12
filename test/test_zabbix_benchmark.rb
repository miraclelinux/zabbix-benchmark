$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require "test/unit/rr"
require 'zabbix-benchmark-test-util'
require 'zabbix-benchmark.rb'

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
end
