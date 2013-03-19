class ZabbixLog
  attr_reader :path
  attr_reader :n_agent_errors
  attr_reader :history_syncer_entries

  def initialize(path)
    @path = path
    @rotation_directory = nil
    clear
  end

  def set_rotation_directory(directory)
    @rotation_directory = directory
  end

  def clear
    @begin_time = nil
    @end_time = nil
    @history_syncer_entries = []
    @poller_entries = []
    @n_agent_errors = 0
  end

  def target_time?(time)
    return false if @begin_time and time < @begin_time
    return false if @end_time and time > @end_time
    return true
  end

  def parse(begin_time = nil, end_time = nil)
    clear
    set_time_range(begin_time, end_time)
    open(@path) do |file|
      file.each do |line|
        if line =~ /^\s*(\d+):(\d{4})(\d\d)(\d\d):(\d\d)(\d\d)(\d\d)\.(\d{3}) (.*)$/
          pid = $1.to_i
          date = Time.local($2.to_i, $3.to_i, $4.to_i,
                            $5.to_i, $6.to_i, $7.to_i, $8.to_i)
          entry = $9

          if target_time?(date)
            parse_entry(pid, date, entry)
          end
        end
      end
    end
  end

  def dbsyncer_total
    total_elapsed = 0
    total_items = 0

    @history_syncer_entries.each do |entry|
      next if entry[:items] <= 0
      next unless target_time?(entry[:date])

      elapsed = entry[:elapsed]
      total_elapsed += elapsed
      total_items += entry[:items]
    end

    average = total_elapsed / total_items.to_f * 1000.0

    #FIXME: should return object
    [average, total_items, total_elapsed]
  end

  def poller_total
    total_items = 0
    total_elapsed = 0
    @poller_entries.each do |entry|
      total_items += entry[:items]
      total_elapsed += entry[:elapsed]
    end
    [total_items, total_elapsed]
  end

  def rotate(suffix = nil)
    suffix ||= "old"
    src = @path
    if @rotation_directory
      dest = "#{@rotation_directory}/#{File.basename(@path)}.#{suffix}"
    else
      dest = "#{@path}.#{suffix}"
    end

    begin
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.mv(src, dest)
    rescue
      $stderr.puts("Warning: Failed to move #{src} to #{dest}! " +
                   "Please check the permission.")
    end
  end

  private
  def set_time_range(begin_time, end_time)
    @begin_time = begin_time
    @end_time = end_time
  end

  def parse_entry(pid, date, entry)
    case entry
    when /\Ahistory syncer #(\d+) \(1 loop\) spent (\d+\.\d+) seconds while processing (\d+) items\Z/
      syncer_id = $1.to_i
      elapsed = $2.to_f
      items = $3.to_i

      element = {
        :pid => pid,
        :syncer_id => syncer_id,
        :date => date,
        :elapsed => elapsed,
        :items => items,
      }
      @history_syncer_entries.push(element)
    when /\Apoller #(\d+) spent (\d+\.\d+) seconds while updating (\d+) values\Z/
      poller_id =  $1.to_i
      elapsed = $2.to_f
      items = $3.to_i

      element = {
        :pid => pid,
        :poller_id => poller_id,
        :date => date,
        :elapsed => elapsed,
        :items => items,
      }
      @poller_entries.push(element)
    when /\AZabbix agent item .+ on host .+ failed: .*\Z/
      @n_agent_errors += 1
    else
    end
  end
end
