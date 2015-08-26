#!/usr/bin/python

import boto.ec2
import sys, getopt

givenid = sys.argv[1]

conn = boto.ec2.connect_to_region("eu-west-1")

conn.terminate_instances(instance_ids=givenid)
