class ZabbixLog
  def initialize(path)
    @path = path
    @history_syncer_entries = []
    @begin_time = nil
    @end_time = nil
  end

  def set_time_range(begin_time, end_time)
    @begin_time = begin_time
    @end_time = end_time
  end

  def parse
    open(@path) do |file|
      file.each do |line|
        if line =~ /^\s*(\d+):(\d{4})(\d\d)(\d\d):(\d\d)(\d\d)(\d\d)\.(\d{3}) (.*)$/
          pid = $1.to_i
          date = Time.local($2.to_i, $3.to_i, $4.to_i,
                            $5.to_i, $6.to_i, $7.to_i, $8.to_i)
          entry = $9

          parse_entry(pid, date, entry)
        end
      end
    end
  end

  def history_sync_average
    total_elapsed = 0
    total_items = 0

    @history_syncer_entries.each do |entry|
      next if entry[:items] <= 0
      elapsed = entry[:elapsed]
      total_elapsed += elapsed
      total_items += entry[:items]
    end

    average = total_elapsed / total_items.to_f * 1000.0
    [average, total_items]
  end

  private
  def parse_entry(pid, date, entry)
    if entry =~ /\Ahistory syncer .* (\d+\.\d+) seconds .* (\d+) items\Z/
      elapsed = $1.to_f
      items = $2.to_i

      element = {
        :pid => pid, :date => date, :elapsed => elapsed, :items => items,
      }
      @history_syncer_entries.push(element)
    end
  end
end
