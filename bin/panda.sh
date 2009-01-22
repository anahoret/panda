#!/bin/sh
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin 
cd /var/local/www/panda
/usr/local/bin/merb -d -e production -p 4001
