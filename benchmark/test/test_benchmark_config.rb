require 'test/unit'
require 'singleton'
require '../lib/benchmark-config.rb'

class BenchmarkConfigTestCase < Test::Unit::TestCase
  def setup
    @config = BenchmarkConfig.instance.reset
    @fixture_file = "fixtures/config.yml"
  end

  def teardown
  end

  def test_uri_from_file
    @config.load_file(@fixture_file)
    assert_equal("http://localhost:8080/zabbix-postgresql/", @config.uri)
  end

  def test_warmup_duration_from_file
    @config.load_file(@fixture_file)
    assert_equal(777, @config.warmup_duration)
  end

  def test_agents_from_file
    expected = [{"ip_address" => "192.168.1.10", "port" => 10052}]
    @config.load_file(@fixture_file)
    assert_equal(expected, @config.agents)
  end

  def test_default_hosts_step
    assert_equal(0, @config.hosts_step)
  end

  def test_agents
    agents = [{"ip_address" => "192.168.1.10", "port" => 10050},
              {"ip_address" => "192.168.1.11", "port" => 10051},]
    @config.agents = agents
    assert_equal(agents, @config.agents)
  end

  def test_default_agents
    expected = [{"ip_address" => "127.0.0.1", "port" => 10050}]
    assert_equal(expected, @config.agents)
  end
end
