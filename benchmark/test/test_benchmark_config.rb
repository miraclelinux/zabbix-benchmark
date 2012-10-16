require 'test/unit'
require '../lib/zabbix-benchmark.rb'

class BenchmarkConfigTestCase < Test::Unit::TestCase
  def setup
    @config = BenchmarkConfig.instance
  end

  def teardown
  end

  def test_default_hosts_step
    assert_equal(0, @config.hosts_step)
  end
end
