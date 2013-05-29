#!/usr/bin/env ruby

$:.unshift(File.expand_path(File.dirname(__FILE__)) + "/../lib")

require 'rubygems'
require 'benchmark-config'
require 'benchmark-result'

config = BenchmarkConfig.instance.reset
config.read_latency["result_file"] = ARGV[0]
result_file = ReadLatencyResult.new(config)
result_file.load

new_rows = []
result_file.each_legend(1) do |legend, rows|
  first = new_rows.empty?
  rows.each_with_index do |row, i|
    if first
      new_rows.push(["History duration [sec]", "History duration [day]"]) if i == 0
      new_rows.push([row[2].to_i, (row[2].to_i / 60 / 60 / 24)])
    end

    new_rows[0].push("#{legend} monitoring targets") if i == 0
    new_rows[i + 1].push(row[3])
  end
end

open(ARGV[1], "w") do |file|
  new_rows.each do |row|
    file << "#{row.join(",")}\n"
  end
end
