#!/bin/sh
export HOME=/root
cd /var/local/www/panda
/usr/local/bin/merb -r bin/notifier.rb -d -e notifier -P log/merb.notifier.pid

