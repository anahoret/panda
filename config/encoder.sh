#!/bin/sh
export HOME=/root
cd /var/local/www/panda
/usr/local/bin/merb -r bin/encoder.rb -d -e encoder -P log/merb.encoder.pid

