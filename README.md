housed
======

The housed is intended to catch and remove "runnaway" processes, memory and 
resources from systems running a batch-queue system, such as Grid Engine or 
LSF etc. The queue-system specific parts is configurable, so one can easily 
extend or switch between them to use it with other queue-systems.

The housed helps a running computer cluster (with a running queue-system) 
to avoid situations where there are "left-over" allocations of resources 
from jobs that from a queue-system perspective is finished.

We call this general method: "house keeping". 

Requirements
------------

* Python
* Bash
* A suported queue system (or adapt your own)
* A TCPI/IP Multicast capable network. (if you need the message functionality)
* Shared disk/mountpoint (NFS works fine).

Behaviour
---------

housed is a bash script running as a daemon on each node in a cluster and 
regularly checks what state the current node is in. It acts if it detects 
that resources are not registered within the queue-system and tried to 
remove them forcefully.

It does not act in a situation where there is a running job according to 
the queue-system. This is to be very safe about not accidentally killing 
a running job.

The states the housed can be in, are explained below:

### State 1 (running)

The node is currently running a job according to the batch queue system. 
The information is collected from the queue system. Nothing is done as 
long we are in state 1.

### State 2 (housekeep)

The node is idle according to the queue system. This is decided by a 
combination of information from the queue system and an analysis of the 
current process list from the unix "ps" command. If both checks indicates 
there is no job running, a housekeeping event occurs.

### State 3 (conflict)

This is a special state who occurs when there are processes running on the 
host, but the queue system indicates that there are no jobs currently 
running on the node. The system will wait in this state for a configurable 
amount of time before it forces a "state 2" (housekeep) transition. The 
reason for this behaviour is that some queue systems seem to response 
incorrect at some times. Hence, additional checks are performed to make 
sure to avoid killing jobs based on wrong information. By setting the 
config variable "HOUSEKEEP_CYCLES=1" you can override this behaviour and 
make the house-keeping event occur immediately. Doing this, means that you 
fully trust the queue system to always respond correctly. 

User interaction
----------------

Housed uses a small python script called mcastr, that listens to IP multicast 
messages and this are a way to communicate with housed from the outside. 
Multicast is a good way to do this, instead of spawning many, many, 
connections in a loaded cluster which is bad for performance.

### mcasts

This is a simple python script who sends standard input to the house keeper.

Example, send a "ping" to the host node1:

	echo "alfa node1 ping" | mcasts

Tail the log:

	tail /shared/path/housed/housed.log

You should see something like:

	[2011-06-17 12:59:39] [node1] pong

### Protocol specification

To send a message to housed, create a multicast package and send to 
224.1.1.2 port 5007 with the following syntax:

	<clustername> <jobid|hostname> <command> <params>

Cluster name and command are mandatory, you may replace 
jobid|hostname with -1 to send to ALL nodes. params are command 
specific.

Example commands:

Suspend housekeeper on all nodes running job 123 for 60 minutes 
on the cluster 'alfa'.

	alfa 123 housekeepoff 60

Suspend housekeeper on the host with the hostname node1 for 60 minutes on alfa
cluster.

	alfa node1 housekeepoff 60

Suspend housekeeper on alfa cluster (hence the -1) for two hours.

	alfa -1 housekeepoff 120

Available commands:

    housekeepoff N   - Disable house keeper for N minutes
    shutdown         - Shut down house keeper
    ping             - "ping" the house keeper
    state            - Output the current state of the house keeper 
                       in the logs.
Logs
----

If you have specified a path in LOGDIR you will see a lot of different log 
files.

### $LOGDIR/housed.log

This contains all normal log data from all nodes. This is a good file to 
start looking in.

### $LOGDIR/housed.kill.log

In case the housekeeper has killed a job, various information are logged 
to this file like processes, running jobs and free resources. 

There are also several directories matching the host names, each directory 
contain a housed.log and housed.kill.log file but only for this specific node. 

Configuration
-------------

There are some configuration options in a file located in 
/etc/housed/housed.conf, these are.

### QU_SYSTEM

Queue system to use, in this example we are using the LSF queue system. 
The queue system specific file in $QU_VAR/$QU_SYSTEM.conf will be sourced.

	QU_SYSTEM=lsf

### QU_VAR

Path to queue system specific files (see: QU_SYSTEM).

	QU_VAR=/var/housed/

### TICK_TIME

Time in seconds for a tick (cycle). This is how often the queue system will 
query the system for information. Please keep this a sane value. Five 
seconds seems to be a good default for our use case.

	TICK_TIME=5

### PROCESS_WHITELIST

A static whitelist of processes, this need to be a regexp accepted by egrep. 
Processes who match this regexp will NOT be killed.

	PROCESS_WHITELIST="68|apache|postfix"

(in this example, pid 68, processes apache and postfix are ignored and will 
not trigger a housekeep, nor be killed by housed.)

### HOUSEKEEP_CYCLES

When the housekeeper are i state 3 (conflict) it will wait for a few cycles 
and finally force a state 2 (housekeep). This variable decides how many 
cycles that should be. Note that the actual time passed will be 
HOUSEKEEP_CYCLES * TICK_TIME in seconds.

	HOUSEKEEP_CYCLES=5

### HOUSED_BIN

Path to the housed script.

	HOUSED_BIN=/usr/bin/housed

### MCASTR

Path to the mcastr script.

	MCASTR=/usr/bin/mcastr

### MCASTR_DATA

Path to mcastr data file, this is a small file who housed writes in to 
communicate between different processes.

	MCASTR_DATA=/tmp/mcastr.data

### MCASTR_LOCK

Path to mcastr lock file

	MCASTR_LOCK=/var/run/mcastr.running

### MCASTR_PID

Path to mcastr pid file. NOTE: this path is hard coded in to mcastr, 
for now DO NOT change this value.

	MCASTR_PID=/tmp/mcastr.pid

### HOUSED_PID

Path to housed pid file

	HOUSED_PID=/var/run/housed.pid

### QU_PROFILE

Path to queue specific bash compatible "profile" file, who will be 
sourced.

	QU_PROFILE=/opt/lsf/conf/profile.lsf

### MY_CLUSTER

The cluster name, use a hard coded string or some logic like the 
following example.

	MY_CLUSTER="$(source $QU_VAR/$QU_SYSTEM.conf; qu_clustername)"

### LOGDIR

A directory where logfiles go, or enter STDOUT to output to standard output.

	#LOGDIR=STDOUT
	LOGDIR="/cluster/$(source $QU_VAR/$QU_SYSTEM.conf; qu_clustername)/housed/"

Technical details
-----------------

### Logic

When housed starts it enters state 0, the housekeeper then queries the queue 
system and analyzes the system processes and makes a decision between with 
state to trigger next.

* State 1 (running)
	* If the queue system tells housed that there is at least one running 
	job on the host, state 1 is always triggered. 
    	* State 1 do not do anything. 
* State 2 (housekeep)
	* This are the housekeep state and is executed when the host is idle, 
	or when enforced from state 3. 
* State 3 (conflict)
	* There are processes on the machine but the queue system says the 
	node should be empty. After a configurable interval state 2 is 
	enforced.

After a state (1, 2, 3) is run the script always return to state 0, and the 
process starts over.

### Messages

There is a subshell that is running the mcastr process in the background, 
it listens for multicast messages. All messages matching the local cluster 
name (found in the configuration) are sent to the main program. The 
information is actually sent by writing the message to a file and sending 
a USR1 signal to the main process. When housed receive the signal it calls 
the function "signal" who make some parsing and has needed logic to parse 
the file for commands.

Housed also listens for SIGINT and kills the subshell and removes pid and 
lock files. If housed dies in an unclean way, the process mcastr may still 
be running and needs to be killed manually. You may also need to remove the 
file mcastr.run (path found in configuration). You will clearly see messages 
in the logs (housed.log) if this is the case. Recent versions of housed 
(version 1+) have the ability to clean up and fix most problems by a simple 
restart of the service.

### Logs

The daemon are writing to several log files, housed.log contains the ordinary 
log data like housed status and response from messages. If a housekeeping event 
is trigged and processes are killed a lot of debugging information is saved in 
housed.kill.log, use the timestamp to search for the data you are interested 
in (omit the seconds). For convenience housed also have separate logs by host 
name. As an example, in node1/housed.log will we only find logs for node1.

Note, the files will grow, there are no built in log rotation. If it is needed 
it needs to be implemented separately outside the housekeeper. 

License
-------

Copyright (C) 2011 by Stefan Berggren <nsg@nsg.cc>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
