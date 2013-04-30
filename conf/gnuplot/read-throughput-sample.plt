#!/usr/bin/env gnuplot

set title "Throughput sample"
set title font "Helvetica,18"

unset key
set terminal png size 1024,768
set dgrid3d 20,20
set view 70,45
set pm3d
#set palette defined (0 "blue", 5000 "red", 10000 "yellow", 15000 "white")

set format x "%.0f"
set format y "\n%.0f"
set format z "%.0f"
set xlabel "\nEnabled items"
set ylabel "\nHistory duration [day]"
set zlabel "Read histories [thousand]" rotate by 90
#set xrange [0:30000]
#set yrange [0:100]
#set zrange [0:20000]

set datafile separator ","
splot "result-read-throughput.csv" using 2:($3/60/60/24):($4/1000) with lines
