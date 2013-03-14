$:.unshift(File.expand_path(File.dirname(__FILE__) + "/../lib"))

require 'rubygems'
require 'test-unit'
require 'zabbix-log'

class ZabbixLogTestCase < Test::Unit::TestCase
  def setup
    @log = ZabbixLog.new("fixtures/dbsync.log")
  end

  def teardown
  end

  def log_with_time_range
    begin_time = Time.local(2012, 11, 28, 15, 28, 50, 000)
    end_time = Time.local(2012, 11, 28, 15, 29, 30, 000)
    @log.parse(begin_time, end_time)
    @log
  end

  def poller_log_with_time_range
    begin_time = Time.local(2013, 1, 23, 17, 45, 9, 000)
    end_time = Time.local(2013, 1, 23, 17, 45, 39, 000)
    log = ZabbixLog.new("fixtures/poller.log")
    log.parse(begin_time, end_time)
    log
  end

  def test_total_items
    @log.parse
    average, total_items = @log.dbsyncer_total
    assert_equal(57987, total_items)
  end

  def test_total_elapsed
    @log.parse
    average, total_items, total_elapsed = @log.dbsyncer_total
    assert_in_delta(923.750163, total_elapsed, 1.0e-9)
  end

  def test_average
    @log.parse
    average, total_items = @log.dbsyncer_total
    assert_in_delta(15.9302975322055, average, 1.0e-9)
  end

  def test_no_agent_errors
    @log.parse
    n_errors = @log.n_agent_errors
    assert_equal(0, n_errors)
  end

  def test_n_agent_errors
    log = ZabbixLog.new("fixtures/agent-error.log")
    log.parse
    n_errors = log.n_agent_errors
    assert_equal(450, n_errors)
  end

  def test_total_items_with_time_range
    average, total_items = log_with_time_range.dbsyncer_total
    assert_equal(13738, total_items)
  end

  def test_average_with_time_range
    average, total_items = log_with_time_range.dbsyncer_total
    assert_in_delta(12.1069669529771, average, 1.0e-9)
  end

  def test_n_agent_errors_with_time_range
    begin_time = Time.local(2012, 11, 22, 14, 56, 00, 500)
    end_time = Time.local(2012, 11, 22, 14, 56, 01, 000)
    log = ZabbixLog.new("fixtures/agent-error.log")
    log.parse(begin_time, end_time)
    n_errors = log.n_agent_errors
    assert_equal(4, n_errors)
  end

  def test_poller_total
    total_items, total_time = poller_log_with_time_range.poller_total
    assert_equal(2256, total_items)
  end

  def test_poller_elapsed
    total_items, total_elapsed = poller_log_with_time_range.poller_total
    assert_in_delta(13.118722, total_elapsed, 1.0e-9)
  end
end
