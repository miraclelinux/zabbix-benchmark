$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require 'singleton'
require 'zabbix-benchmark-test-util'
require 'benchmark-config'
require 'tempfile'

class BenchmarkConfigTestCase < Test::Unit::TestCase
  include ZabbixBenchmarkTestUtil

  def setup
    @config = BenchmarkConfig.instance.reset
    @fixture_file = fixture_file_path("config.yml")
  end

  def teardown
    @config.reset
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

  class BenchmarkConfigOverrideTestCase < Test::Unit::TestCase
    include ZabbixBenchmarkTestUtil

    def setup
      @config = BenchmarkConfig.instance.reset
      @fixture_file = fixture_file_path("config.yml")
    end

    def teardown
      @config.reset
    end

    data do
      data_set = {}
      data_set["override uri"] = ["http://localhost/expected", "@uri"]
      data_set["override login_user"] = ["user", "@login_user"]
      data_set["override login_pass"] = ["passwd", "@login_pass"]
      data_set["override num_hosts"] = ["user", "@num_hosts"]
      data_set["override hosts_step"] = ["user", "@hosts_step"]
      data_set["override custom_agents"] = [
                                            {:ip_adress => "192.168.1.100"},
                                            "@custom_agents"
                                           ]
      data_set["override warmup_duration"] = ["1000", "@warmup_duration"]
      data_set["override measurement_duration"] = ["1000", "@measurement_duration"]
      data_set
    end

    def test_override_config(data)
      @config.load_file(@fixture_file)
      expected_value, target = data
      @config.uri = expected_value
      @config.instance_variable_set(target, expected_value)
      Tempfile.open("config.yml", "/tmp") do |file|
        @config.export(file.path)
        @config.load_file(file.path)
        actual_value = @config.instance_variable_get(target)
        assert_equal(expected_value, actual_value)
      end
    end
  end
end

