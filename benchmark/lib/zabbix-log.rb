class ZabbixLog
  def initialize(path)
    @path = path
    @history_syncer_entries = []
  end

  def parse
    file = open(@path)
    file.each do |line|
      if line =~ /^\s*(\d+):(\d{4})(\d\d)(\d\d):(\d\d)(\d\d)(\d\d)\.(\d{3}) (.*)$/
        pid = $1.to_i
        date = Time.local($2.to_i, $3.to_i, $4.to_i,
                          $5.to_i, $6.to_i, $7.to_i, $8.to_i)
        entry = $9

        parse_entry(pid, date, entry)
      end
    end
    file.close
  end

  def history_sync_average
    elapsed_sum = 0
    items_sum = 0

    @history_syncer_entries.each do |entry|
      elapsed = entry[:elapsed]
      elapsed_sum += elapsed
      items_sum += entry[:items]
    end

    average = elapsed_sum / items_sum.to_f * 1000.0
    [average, items_sum]
  end

  private
  def parse_entry(pid, date, entry)
    if entry =~ /\Ahistory syncer .* (\d+\.\d+) seconds .* (\d+) items\Z/
      elapsed = $1.to_f
      items = $2.to_i
      return if items <= 0

      element = {
        :pid => pid, :date => date, :elapsed => elapsed, :items => items,
      }
      @history_syncer_entries.push(element)
    end
  end
end
