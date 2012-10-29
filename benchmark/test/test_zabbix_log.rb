require 'test/unit'
require '../lib/zabbix-log.rb'

class ZabbixLogTestCase < Test::Unit::TestCase
  def setup
    @log = ZabbixLog.new("fixtures/dbsync.log")
  end

  def teardown
  end

  def test_total_items
    @log.parse
    average, total_items = @log.history_sync_average
    assert_equal(42, total_items)
  end

  def test_average
    @log.parse
    average, total_items = @log.history_sync_average
    assert_in_delta(1.052785714, average, 0.000000001)
  end
end
