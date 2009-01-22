#!/bin/sh
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /var/local/www/panda
/usr/local/bin/merb -r bin/encoder.rb -d -e encoder -P log/merb.encoder.pid
