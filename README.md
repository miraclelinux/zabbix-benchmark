zabbix-benchmark README
=======================

What's this?
------------

zabbix-benchmark is a benchmark suite for Zabbix.


Writing performance benchmark
-----------------------------

### Setup Zabbix environment

#### Setup Zabbix server

If you use normal version of Zabbix, please apply the following patch then
build & install it.

* patches/zabbix-2.0.3-histsync-log.patch
* patches/zabbix-2.0.3-poller-log.patch

If you use Zabbix with HistoryGluon, please add following line to your
zabbix-server.conf.

    BenchmarkMode=1

#### Modify zabbix-server.conf

Set LogFileSize to 1024 because current zabbix-benchmark can't measure number
of written histories correctly when the log file is overflowed while running
the benchmark.

    LogFileSize=1024

In addition, set DisableHousekeeping to 1 because we should suppress load
variation influence caused by house keeper.

    DisableHousekeeping=1

#### Prepare monitoring targets

Prepare some linux hosts as monitoring target, then run Zabbix agent on them
by usual procedure. You shoud prepare at least one targe host although it's
better to prepare more hosts. zabbix-benchmark try to apply load to Zabbix
server by registering many dummy hosts with a same real zabbix-agent.

#### Register monitoring template

Use the following monitoring template for the benchmark.

* conf/zabbix/template-linux-5sec.xml
  * Number of monitoring items: 102
  * Update interval: 5sec

Please import the above template through the Web interface of Zabbix.


### Setup zabbix-benchmark

#### Install Ruby

On CentOS or Scientific Linux, please install ruby & gem by following command.

    # yum install rubygems ruby-devel

#### Install ZabbixAPI library

zabbix-benchmark uses a third-party library "zbxapi".
You can install zbxapi by following command.

    # gem install zbxapi

zabbid-benchmark is confirmed with zbxapi Version 0.2.415. If you can't run it
with different version of zbxapi, please install zbxapi-0.2.415 with following
command:

   $ gem install zbxapi -v 0.2.415

#### Setup the configuration file

Copy conf/config-sample.yml to conf/config.yml then modify it suitably.  
Known values are:

* uri
  * URI of Zabbix Web frontent.
* login_user
  * Login user name of Zabbix Web frontend.
  * The user must be permitted to use API.
  * On Zabbix 2.0, the user "Admin" is permitted to use API by default.
* login_pass
  * Password of the user
* num_host
  * Max number of hosts to register.
  * zabbix-benchmark increases registerd hosts step by step until this value,
    then measures on each step.
* hosts_step
  * Number of hosts to increase on a step.
* host_group
  * A host group to register dummy hosts.
  * The group must be registerd by hand before run the benchmark.
* template_name
  * Template to use for the benchmark.
  * The template should be imported by hand before run the benchmark.
* agents
  * IP address & port of a zabbix agent.
  * If you add multiple zabbix agents, they are shared equally among all dummy
    hosts.
  * If you don't set it, 127.0.0.1:10050 is used by default.
* zabbix_log_file
  * The path of the log file of Zabbix server
* rotate_zabbix_log
  * If true, zabbix-benchmark will rotate Zabbix server log on each step.
* write_throughput_result_file
  * The file path to output results of write-throughput benchmark.
* warmup_duration
  * Warm up time for a step (in sec).
  * You should specify longer time than CacheUpdateFrequency in
    zabbix_server.conf.
* measurement_duration
  * Measurement time for a step (in sec).
* self_monitoring_items
  * A history item to fetch from Zabbix. Specify hostname and key of the item
    and a file path to output.
  * You can specify multiple items.

#### Connection test

Run the following command to test connection to Zabbix frontent.

    $ ./zabbix-benchmark api_version

You can see a following output when there is no problem.

    1.4

#### Register dummy hosts

Run the following command to register dummy hosts to Zabbix:

    $ ./zabbix-benchmark setup


### Run writing performance benchmark

#### About permission

You should run zabbix-benchmark with "zabbix" user privilege because it try to
rotate Zabbix server's log file while running benchmark.

#### Command

Run zabbix-benchmark with following command:

    $ ./zabbix-benchmark writing_benchmark

When the benchmark is completed, results are writed to the file which is
specified by write_throughput_result_file in the config file.

When you interrupt or fail the benchmark, run following command to reset the
state:

    $ ./zabbix-benchmark disable_all_hosts


#### Contents of an output file

The format of an output file is CSV.  
Columns are:

* Begin time
* End time
* Number of enabled hosts
* Number of enabled items
* Average time to write a history [msec]
* Total number of written histories in measurement duration
* Total processing time to write histories in measurement duration [sec]
* Total number of read histories in measurement duration by poller
* Total processing time to read histories in measurement duration [sec]
* Number of error log entries of communication with Zabbix agent


Reading performance benchmark
-----------------------------

### Setup the configuration file

Copy conf/config-sample-reading.yml to conf/config.yml then modify it
suitably. For reading performance benchmark, same config items with writing
performance benchmark are required because it also measure reading performance
under heavy writing load. In addition to them, following config items are
provided for reading performance benchmark.

* mysql: MySQL connection settings
  * host: Host name
  * username: User name
  * password: Password
  * database: Databse name
* postgresql: PostgreSQL connection setteings
  * host: Host name
  * username: User name
  * password: Password
  * database: Database name
* history_gluon: HistoryGluon connection settings
  * host: Host name
  * port: Port number
  * database: Database name
* history_data: Setup settings for history data.
  How to setup history data is described later.
  * begin_time: The time of the the first history record
  * end_time: The time of the last history record
  * interval_uint: Interval of uint item[sec]
  * interval_float: Interval of float item[sec]
  * interval_string: Interval of string item[sec]
  * num_hosts: Number of hosts to setup. Although you should setup all history
    records for all dummy hosts, you can limit the number of hosts to setup by
    this setting if it's too slow to do it.
* history_duration_for_read: History duration to read in a request. While
  running benchmark it increases the history duration step by step from min
  to max, then measure latency & throughput of each steps.
  * step: Amount of seconds to increase in a step [sec]
  * min: Minimum history duration [sec]
  * max: Maximum history duration [sec]
* read_latency: Settings for read latency benchmark
  * try_count: Number of times to measure latency on each steps
  * result_file: Output path of results of read latency benchmark. The default
    value is "output/result-read-latency.csv"
* read_throughput: Settings for read throughput benchmark
  * num_thread: Number of threads to read
  * result_file: Output path of results of read throughput benchmark. The
    default value is "output/result-read-throughput.csv"


### Install additional ruby libraries

If you want to use MySQL as history DB, you need to install mysql2 package.
To install it, development packages of Ruby and MySQL are required.

For CentOS or Scientific Linux:

    # yum install gcc ruby-devel mysql-devel
    # gem install mysql2

If you want to use MySQL as history DB, you need to install pg package. To
install it, development packages of Ruby and PostgreSQL are required.

For CentOS or Scientific Linux:

    # yum install gcc ruby-devel postgresql-devel
    # gem install pg

If you want to use HistoryGluon as history DB, you need to install the ruby
binding of HistoryGluon.

For CentOS or Scientific Linux:

    # yum install gcc ruby-devel
    $ git clone git@github.com:miraclelinux/HistoryGluon.git
    (Please refere README in it to install HistoryGluon itself)
    $ cd HistoryGluon/client-ruby-ext
    $ ruby extconf.rb
    $ make
    # make install


### Setup history data

There is a sub command "fill_history" in zabbix-benchmark to setup history
data. You need to setup history data to each DBs you use before running
benchmark.

If you want to set up history data to MySQL, add "mysql" option to the command:

    $ ./zabbix-benchmark fill_history mysql

If you want to set up history data to PostggreSQL, add "postgresql" option to
the command:

    $ ./zabbix-benchmark fill_history postgresql

If you want to set up history data to any DBs via HistoryGluon, add
"history-gluon" option to the command:

    $ ./zabbix-benchmark fill_history history-gluon

Please notice that you also need to switch backend DBs by HistoryGluon.

You can removed these data by "clear_history" command. DB options for it are
same with "fill_history" command.


### Run reading performance benchmark

Run following command to launch reading performance benchmark:

    $ ./zabbix-benchmark reading_benchmark

If you run reading_benchmark sub command without options, it read history data
via Zabbix frontend and measures its performance. If you want to measure read
performance of direct connection to DBs, add same DB options with
"fill_history" to reading_benchmark.

For MySQL:

    $ ./zabbix-benchmark reading_benchmark mysql

For PostgreSQL:

    $ ./zabbix-benchmark reading_benchmark postgresql

For HistoryGluon:

    $ ./zabbix-benchmark reading_benchmark history-gluon


#### Contents of an output file

##### Results of read latency benchmark

By default results of read throughput benchmark are output to
"output/result-read-latency.csv" whose format is CSV.

Included columns in the file are:

* Number of enabled hosts
* Number of enabled items
* History duration [sec]
* Average of read latency [sec]
* Succeeded read count
* Failed read count

##### Results of read throughput benchmark

By default results of read throughput benchmark are output to
"output/result-read-throughput.csv" whose format is CSV.

Included columns in the file are:

* Number of enabled hosts
* Number of enabled items
* History duration [sec]
* Total number of read history records in measurement_duration
* Total processing time to read in measurement_duration
  (Sum of real processing times in each threads)
* Total number of written history in measurement_duration
