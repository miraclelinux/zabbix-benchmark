zabbix-benchmark README
=======================

What's this?
------------

This is a benchmark suite for Zabbix.
Currently, it supports only measuring write performance of histories.


Setup
-----

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


Run write performance benchmark
-------------------------------

### About permission

You should run zabbix-benchmark with "zabbix" user privilege because it try to
rotate Zabbix server's log file while running benchmark.

### Command

Run zabbix-benchmark with following command:

    $ ./zabbix-benchmark

When the benchmark is completed, results are writed to the specified file.

### Contents of an output file

The format of an output file is CSV.
Columns are:

* Begin time
* End time
* Number of enabled hosts
* Number of enabled items
* Average time to write an item [msec]
* Total number of written histories in measurement duration
* Total processing time to write histories in measurement duration [sec]
* Number of error log entries of communication with Zabbix agent
