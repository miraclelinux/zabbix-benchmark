require 'test/unit'
require '../lib/zabbix-benchmark.rb'

class ZabbixBenchmarkTestCase < Test::Unit::TestCase
  def setup
    @benchmark = ZabbixBenchmark.new
  end

  def teardown
  end
end
