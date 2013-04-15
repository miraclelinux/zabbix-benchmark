$:.unshift(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'time'
require 'benchmark-config'

class HistoryDatabase
  DB_HISTORY_GLUON = "history-gluon"
  DB_MYSQL         = "mysql"

  def self.known_db?(type)
    [DB_HISTORY_GLUON, DB_MYSQL].include?(type)
  end

  def initialize(config, backend)
    @config = config
    @history_gluon = nil
    @mysql = nil
    open_db(backend)
  end

  def get_histories(item, begin_time, end_time)
    if @hgl
      get_histories_from_hgl(item, begin_time, end_time)
    elsif @mysql
      get_histories_from_mysql(item, begin_time, end_time)
    else
      raise "No Database is specified!"
    end
  end

  def setup_histories(item)
    if @hgl
      setup_histories_by_hgl(item)
    elsif @mysql
      setup_histories_by_sql(item)
    else
      raise "No Database is specified!"
    end
  end

  private
  def open_db(backend)
    case backend
    when DB_HISTORY_GLUON
      require 'historygluon'
      conf = @config.history_gluon
      @hgl = HistoryGluon.new(conf["database"], conf["host"], conf["port"])
    when DB_MYSQL
      require 'mysql2'
      conf = @config.mysql
      @mysql = Mysql2::Client.new(:host     => conf["host"],
                                  :username => conf["username"],
                                  :password => conf["password"],
                                  :database => conf["database"])
    else
      raise "Unknown DB is specified!"
    end
  end

  def get_histories_from_hgl(item, begin_time, end_time)
    @hgl.range_query(item["itemid"].to_i,
                     begin_time.to_i, begin_time.usec * 1000,
                     end_time.to_i, end_time.usec * 1000,
                     HistoryGluon::SORT_ASCENDING,
                     HistoryGluon::NUM_ENTRIES_UNLIMITED)
  end

  def get_histories_from_mysql(item, begin_time, end_time)
    table, _, _ = params_for_value_type(item["value_type"].to_i)
    itemid = item["itemid"].to_i

    query  = "SELECT h.* FROM #{table} h"
    query += "  WHERE (h.itemid IN ('#{itemid}'))"
    query += "    AND h.itemid BETWEEN 000000000000000 AND 099999999999999"
    query += "    AND h.clock>=#{begin_time.to_i}"
    query += "    AND h.clock<=#{end_time.to_i};"

    result = []
    @mysql.query(query, :as => :hash).each do |row|
      result.push(row)
    end
    result
  end

  def params_for_value_type(value_type)
    conf = @config.history_data
    case value_type
    when ZbxAPIUtils::VALUE_TYPE_INTEGER
      ['history_uint', '1', conf["interval"]]
    when ZbxAPIUtils::VALUE_TYPE_STRING
      ['history_str', '"dummy"', conf["interval"]]
    else
      ['history', '1.0', conf["interval_string"]]
    end
  end

  def insert_query_for_one_day(table, item, clock_offset)
    itemid = item["itemid"].to_i
    table, value, interval = params_for_value_type(item["value_type"].to_i)
    last_clock = clock_offset + 60 * 60 * 24 - interval
    query = "INSERT INTO #{table} (itemid, clock, ns, value) VALUES "
    clock_offset.step(last_clock, interval) do |clock|
      query += "(#{itemid}, #{clock}, 0, #{value})"
      query += ", " if clock < last_clock
    end
    query += ";"
    query
  end

  def setup_histories_by_sql(item)
    conf = @config.history_data
    begin_time = Time.parse(conf["begin_time"])
    end_time = Time.parse(conf["end_time"])
    step = 60 * 60 * 24

    begin_time.to_i.step(end_time.to_i, step) do |clock_offset|
      query = insert_query_for_one_day("history", item, clock_offset);
      @mysql.query(query)
    end
  end

  def setup_histories_by_hgl(item)
    conf = @config.history_data
    itemid = item["itemid"].to_i
    _, value, step = params_for_value_type(item["value_type"].to_i)
    begin_time = Time.parse(conf["begin_time"])
    end_time = Time.parse(conf["end_time"])

    puts "string" if item["value_type"].to_i == ZbxAPIUtils::VALUE_TYPE_STRING

    begin_time.to_i.step(end_time.to_i, step) do |clock|
      case item["value_type"].to_i
      when ZbxAPIUtils::VALUE_TYPE_INTEGER
        @hgl.add_uint(itemid, clock, 0, value.to_i)
      when ZbxAPIUtils::VALUE_TYPE_FLOAT
        @hgl.add_float(itemid, clock, 0, value.to_f)
      when ZbxAPIUtils::VALUE_TYPE_STRING
        @hgl.add_string(itemid, clock, 0, value)
      else
        raise "Invalid value type: #{item["value_type"]}"
      end
    end
  end
end
