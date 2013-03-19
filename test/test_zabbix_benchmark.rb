$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require "test/unit/rr"
require 'zabbix-benchmark-test-util'
require 'zabbix-benchmark'

class ZabbixBenchmarkChild <  ZabbixBenchmark
  attr_accessor :zabbix, :zabbix_log
end

class ZabbixBenchmarkTestCase < Test::Unit::TestCase
  include ZabbixBenchmarkTestUtil

  def setup
    @zabbix = ZbxAPIUtils.new("http://test-host/", "Admin", "zabbix")
    @zabbix_log = ZabbixLog.new(nil)
    stub(@zabbix).ensure_loggedin
    stub(@zabbix).API_version { "1.4\n" }
    stub(@zabbix_log).parse
    stub(@zabbix_log).rotate
    @benchmark = benchmark
  end

  def teardown
    FileUtils.rm_rf(File.dirname(__FILE__) + "/output")
    BenchmarkConfig.instance.reset
  end

  def benchmark
    benchmark = ZabbixBenchmarkChild.new
    benchmark.zabbix = @zabbix
    benchmark.zabbix_log = @zabbix_log
    benchmark
  end

  def test_api_version
    version_string = capture do
      @benchmark.api_version
    end
    assert_equal("1.4\n", version_string)
  end

  def test_enable_12_hosts
    BenchmarkConfig.instance.num_hosts = 20
    mock(@zabbix).enable_hosts(hostnames(10)).once
    mock(@zabbix).enable_hosts(hostnames(2, 10)).once
    output = capture do
      benchmark.enable_n_hosts("12")
    end
    assert_equal("Enable 12 dummy hosts ...\n", output)
  end

  def test_enable_all_hosts
    BenchmarkConfig.instance.num_hosts = 41
    mock(@zabbix).enable_hosts(hostnames(10)).once
    mock(@zabbix).enable_hosts(hostnames(10, 10)).once
    mock(@zabbix).enable_hosts(hostnames(10, 20)).once
    mock(@zabbix).enable_hosts(hostnames(10, 30)).once
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
    mock(@zabbix).get_items_range(hostnames(10)) { [72373, 72984] }.once
    output = capture do
      benchmark.print_cassandra_token(n_hosts)
    end
    expected = File.read(fixture_file_path(expected))
    assert_equal(expected, output)
  end

  def hostids(n_hosts)
    n_hosts.times.collect { |i| (100 + i).to_s }
  end

  def hostnames(n_hosts, base = 0)
    n_hosts.times.collect { |i| "TestHost#{base + i}" }
  end

  def hosts(n_hosts)
    n_hosts.times.collect do |i|
      { "hostid" => (100 + i).to_s, "host" => "TestHost#{i}" }
    end
  end

  def items(n_items)
    n_items.times.collect do |i|
      { "itemid" => (1000 + i).to_s }
    end
  end

  def expected_output_one_step(n_hosts, base, warmup, measure, results)
    names = hostnames(n_hosts, base)
    <<EOS
Enable #{names.length} dummy hosts: 
["#{names.join('", "')}"]

Enabled hosts: #{names.length + base}
Enabled items: #{(names.length + base) * 2}

Warmup #{warmup} seconds ...
Measuring write performance for #{measure} seconds ...
Collecting results ...
DBsync average: #{results[0]} [msec/item]
Total #{results[1]} items are written
EOS
  end

  def expected_output(n_steps, step, warmup, measure, results)
    output = ""
    n_steps.times do |i|
      output += expected_output_one_step(step, step * i,
                                         warmup, measure,
                                         results[i])
      output += "\n"
    end
    output += "Disable all dummy hosts ...\n"
  end

  def test_run_without_setup
    config = BenchmarkConfig.instance
    config.num_hosts = 6
    config.hosts_step = 3
    config.warmup_duration = 0.3
    config.measurement_duration = 0.6

    dummy_results = [
      [0.123, 234, 28.782],
      [0.321, 432, 138.672]
    ]

    mock(@zabbix).get_enabled_test_hosts{[]}.once

    mock(@zabbix).enable_hosts(hostnames(3)).once
    mock(@zabbix).get_enabled_hosts { hosts(3) }.once
    mock(@zabbix).get_enabled_items(hostids(3)) { items(6) }.once
    mock(@zabbix_log).dbsyncer_total{dummy_results[0]}.once

    mock(@zabbix).enable_hosts(hostnames(3, 3)).once
    mock(@zabbix).get_enabled_hosts { hosts(6) }.once
    mock(@zabbix).get_enabled_items(hostids(6)) { items(12) }.once
    mock(@zabbix_log).dbsyncer_total{dummy_results[1]}.once

    mock(@zabbix).disable_hosts(hostnames(6)).once

    output = capture do
      benchmark.run_without_setup
    end

    assert_equal(expected_output(2, 3, 0.3, 0.6, dummy_results), output)
  end
end
