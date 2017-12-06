#!/bin/sh
job=`kubectl  get job -n  ceph |awk '{print $1}'`

while read line
do
  kubectl  delete job  $line -n  ceph
done
