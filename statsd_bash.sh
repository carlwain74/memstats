#!/bin/bash

STATSD_SERVER=10.1.1.1
STATSD_PORT=9191
SERVER_FILE=server.txt
RUSER=cloud_user
CONFIG_CHECK=0
LOG_LEVEL=5

verbosity=5 # default to show warnings
silent_lvl=0
crt_lvl=1
err_lvl=2
wrn_lvl=3
inf_lvl=4
dbg_lvl=5

notify() { log $silent_lvl "NOTE: $1"; } # Always prints
critical() { log $crt_lvl "CRITICAL: $1"; }
error() { log $err_lvl "ERROR: $1"; }
warn() { log $wrn_lvl "WARNING: $1"; }
inf() { log $inf_lvl "INFO: $1"; } # "info" is already a command
debug() { log $dbg_lvl "DEBUG: $1"; }
log() {
    if [ $verbosity -ge $1 ]; then
        datestring=`date +'%Y-%m-%d %H:%M:%S'`
        echo -e "[$datestring] $2"
    fi
}

#
# ping_check
#
# Desc: Function to ping a remote server to determine availability
# Inputs: Server (IP/FQDN)
# Return: PING_RES (Success=1; Failure=0)
ping_check()
{
   debug "ping_check: START"
   inf "Checking status of $1"

   ping -q -c1 $1 > /dev/null

   if [ $? -eq 0 ]; then
      PING_RES=1
      debug "ping_check: Success"
   else
      PING_RES=0
      warn "ping_check: Server [$1] failed to respond"
   fi
   
   debug "ping_check: END"
}

#
# send_stats
#
# Desc: Push stats to stat server
# Input: Server Name, Server Location, Memory, Process
# Return: None
# 
send_stats()
{
  #echo '$1.memory.:1|c' | nc -C -w1 -u ${STATSD_SERVER} ${STATSD_PORT}

  debug "Send Stats: START"
  inf "$1 $2 $3 $4"
  debug "Send Stats: END"
}

#
# read_config
#
# Desc: Read config file
# Input: None
# Return: None
#
read_config()
{
   debug "read_config: START"

   ## Check config file exists
   if [ -e config.txt ]; then
      debug "Processing config file"
      while read -r option value; do
         debug "OPTION: $option; VALUE: $value"
         if [ $option == "STATSD_SERVER" ] && [ $value != "" ]; then
            debug "CONFIG: $option | $value"
            STATSD_SERVER=$value
            CONFIG_CHECK=$((CONFIG_CHECK+1))
         elif [ $option == "STATSD_PORT" ] && [ $value != "" ]; then
            debug "CONFIG: $option | $value"
            STATSD_PORT=$value
            CONFIG_CHECK=$((CONFIG_CHECK+1))
         elif [ $option == "SERVER_FILE" ] && [ $value != "" ]; then
            debug "CONFIG: $option | $value"
            SERVER_FILE=$value
            CONFIG_CHECK=$((CONFIG_CHECK+1))
         elif [ $option == "REMOTE_USER" ] && [ $value != "" ]; then
            debug "CONFIG: $option | $value"
            RUSER=$value
            CONFIG_CHECK=$((CONFIG_CHECK+1))
         fi
      done < config.txt
   fi

   if [ $CONFIG_CHECK != 4 ] ; then
      critical "Not all config parameters are defined! [Detected: $CONFIG_CHECK]"
      exit -1
   fi

   debug "read_config: END"
}

#
# process_server
#
# Desc: Process stats for server
# Input: Server Name, Server Location
# Return: None
#
process_server()
{
   debug "process_server: START"

   # Check server is available
   ping_check $server_loc

   if [ $PING_RES -eq 0 ]; then
      critical "Server $server_id is unreachable"
   else
      # Check server responds to ssh
      ssh -q $RUSER@$server_loc exit

      # Connect to server and iterate each process and memory
      if [ $? == 0 ]; then
         debug "Server [server_loc] is available"
         ssh $RUSER@$server_loc "ps -eo rss,command --sort rss" | grep -v grep | grep -v "ps -eo" | awk '{printf $1/1024 "MB"; $1=""; print}'\
         | while read -r mem cmd; do
            send_stats $server_id $server_loc $mem $cmd
          done
      else
         critical "Unable to connect to $server_loc"
      fi
   fi
   debug "process_server: END"
}

# Read configuration file
read_config

# Main loop

## Check server file exists
if [ ! -e $SERVER_FILE ]; then
   critical "ERROR: $SERVER_FILE does not exist!"
   exit -1
fi

## Process each server
while read -r server_id server_loc
do
   inf "Processing $server_id | $server_loc"
   process_server $server_id $server_loc &
done < $SERVER_FILE
