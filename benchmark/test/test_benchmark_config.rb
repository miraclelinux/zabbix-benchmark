require 'test/unit'
require 'singleton'
require '../lib/zabbix-benchmark.rb'

class BenchmarkConfigTestCase < Test::Unit::TestCase
  def setup
    @config = BenchmarkConfig.instance.reset
  end

  def teardown
  end

  def test_default_hosts_step
    assert_equal(0, @config.hosts_step)
  end

  def test_agents
    agents = [{:ip_address => "192.168.1.10", :port => 10050},
              {:ip_address => "192.168.1.11", :port => 10051},]
    @config.custom_agents = agents
    assert_equal(agents, @config.agents)
  end

  def test_default_agents
    expected = [{:ip_address => "127.0.0.1", :port => 10050}]
    assert_equal(expected, @config.agents)
  end
end
