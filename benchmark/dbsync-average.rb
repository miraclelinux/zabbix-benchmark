#!/usr/bin/env ruby

log_filename = ARGV[0]

elapsed_sum = 0
items_sum = 0
elapsed_max = 0

file = open(log_filename)

file.each do |line|
  if line =~ /^\s*(\d+):(\d{4})(\d\d)(\d\d):(\d\d)(\d\d)(\d\d)\.(\d{3}) history syncer .* (\d+\.\d+) seconds .* (\d+) items$/
    pid = $1.to_i
    date = Time.local($2.to_i, $3.to_i, $4.to_i,
                      $5.to_i, $6.to_i, $7.to_i, $8.to_i)
    elapsed = $9.to_f
    items = $10.to_i
    next if items <= 0

    elapsed_sum += elapsed
    items_sum += items
    elapsed_max = elapsed if elapsed > elapsed_max
  end
end

file.close

average = elapsed_sum / items_sum.to_f * 1000.0

puts "average: #{average} [msec/item]"
puts "total: #{items_sum} items"
puts "elapsed_max: #{elapsed_max}"
