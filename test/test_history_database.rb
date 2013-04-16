$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'test-unit'
require "test/unit/rr"
require 'history-database'
require 'historygluon'

class HistoryMySQLChild < HistoryMySQL
  attr_accessor :mysql
end

class HistoryHGLChild < HistoryHGL
  attr_accessor :hgl
end

class HistoryDatabaseTestCase < Test::Unit::TestCase
  def setup
    @config = BenchmarkConfig.instance
  end

  def teardown
    @config.reset
  end

  data("history-gluon" => [true, "history-gluon"],
       "mysql"         => [true, "mysql"],
       "hoge"          => [false, "hoge"])
  def test_known_db?(data)
    expected, type = data
    assert_equal(expected, HistoryDatabase.known_db?(type))
  end

  def test_get_histories_by_hgl
    expected = [
                {
                  :id    => 321,
                  :sec   => 10,
                  :ns    => 0,
                  :type  => 3,
                  :value => 555,
                }
               ]
    conf = @config.history_gluon
    db = HistoryHGLChild.new(@config)
    mock(db.hgl).range_query(321, 0, 0, 12345, 0,
                             HistoryGluon::SORT_ASCENDING,
                             HistoryGluon::NUM_ENTRIES_UNLIMITED).once do
      expected
    end
    actual = db.get_histories({"itemid" => "321", "value_type" => "3"},
                              Time.at(0), Time.at(12345))
    assert_equal(expected, actual);
  end

  def test_get_histories_by_mysql
    query  = "SELECT h.* FROM history_uint h"
    query += "  WHERE (h.itemid IN ('321'))"
    query += "    AND h.itemid BETWEEN 000000000000000 AND 099999999999999"
    query += "    AND h.clock>=0"
    query += "    AND h.clock<=12345;"
    expected = [
                {
                  "itemid" => 321,
                  "clock"  => 10,
                  "ns"     => 0,
                  "value"  => 555,
                }
               ]
    conf = @config.mysql
    db = HistoryMySQLChild.new(@config)
    mock(db.mysql).query(query, {:as => :hash}).once { expected }
    actual = db.get_histories({"itemid" => "321", "value_type" => "3"},
                              Time.at(0), Time.at(12345))
    assert_equal(expected, actual);
  end
end
