require 'rubygems'
gem 'test-unit'
require 'test/unit'
require "test/unit/rr"
require '../lib/zbxapi-utils.rb'
require '../lib/zabbix-benchmark.rb'

class ZabbixBenchmarkTestCase < Test::Unit::TestCase
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
    benchmark = ZabbixBenchmark.new
    benchmark.zabbix = @zabbix
    benchmark
  end

  def capture
    original_stdout = $stdout
    dummy_stdio = StringIO.new
    $stdout = dummy_stdio
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    dummy_stdio.string
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
    benchmark.enable_n_hosts("12")
  end
end
