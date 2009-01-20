#!/bin/sh
export HOME=/root
cd /var/local/www/panda
/usr/local/bin/merb -d -e production -p 4001

