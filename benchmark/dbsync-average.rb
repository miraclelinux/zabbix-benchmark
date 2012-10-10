#!/usr/bin/env ruby

log_filename = ARGV[0]

time_sum = 0
items_sum = 0
time_max = 0

file = open(log_filename)

file.each do |line|
  if line =~ /.* history syncer .* (\d+\.\d+) seconds .* (\d+) items/
    time = $1.to_f
    items = $2.to_i
    next if items <= 0

    time_sum += time
    items_sum += items
    time_max = time if time > time_max
  end
end

file.close

average = time_sum / items_sum.to_f * 1000.0

puts "average: #{average} [msec/item]"
puts "total: #{items_sum} items"
puts "time_max: #{time_max}"
