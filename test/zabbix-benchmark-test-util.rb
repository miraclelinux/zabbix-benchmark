module ZabbixBenchmarkTestUtil
  private
  def capture
    original_stdout = $stdout
    dummy_stdio = StringIO.new
    $stdout = dummy_stdio
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    dummy_stdio.string
  end

  def fixture_file_path(file_name)
    base_dir = File.dirname(__FILE__)
    File.join(base_dir, "fixtures", file_name)
  end
end
