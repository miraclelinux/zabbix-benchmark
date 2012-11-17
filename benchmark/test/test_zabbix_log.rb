require 'test/unit'
require '../lib/zabbix-log.rb'

class ZabbixLogTestCase < Test::Unit::TestCase
  def setup
    @log = ZabbixLog.new("fixtures/dbsync.log")
  end

  def teardown
  end

  def log_with_time_range
    begin_time = Time.local(2012, 10, 17, 17, 10, 05, 733)
    end_time = Time.local(2012, 10, 17, 17, 10, 06, 000)
    @log.set_time_range(begin_time, end_time)
    @log.parse
    @log
  end

  def test_total_items
    @log.parse
    average, total_items = @log.history_sync_average
    assert_equal(42, total_items)
  end

  def test_total_elapsed
    @log.parse
    average, total_items, total_elapsed = @log.history_sync_average
    assert_in_delta(0.044217, total_elapsed, 1.0e-9)
  end

  def test_average
    @log.parse
    average, total_items = @log.history_sync_average
    assert_in_delta(1.052785714, average, 1.0e-9)
  end

  def test_total_items_with_time_range
    average, total_items = log_with_time_range.history_sync_average
    assert_equal(15, total_items)
  end

  def test_average_with_time_range
    average, total_items = log_with_time_range.history_sync_average
    assert_in_delta(0.999066667, average, 1.0e-9)
  end
end
