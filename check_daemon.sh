#!/bin/bash

PID="`cat /var/run/vpsadmin.pid`"
if [ ! -f /proc/$PID/status ]; then
	rm /var/run/vpsadmin.pid
	php /opt/vpsadmin/daemon.php
	echo "`hostname`: daemon dead, starting." | mail -s "`hostname`: starting vpsAdmin daemon" snajpa@snajpa.net -- -from vpsadmin@vpsfree.cz
fi

