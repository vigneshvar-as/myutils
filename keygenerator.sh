while [ 1 ]
do
	cat /var/log/httpd/access_log | grep keygen | tail -n 1 > /tmp/keygen
	state=`diff /opt/lastaccess /tmp/keygen | wc -l`
        if [ $state -ne 0 ]
	then
		/opt/consul keygen > /var/www/html/repo/keygen
		cp /tmp/keygen /opt/lastaccess
	fi
	sleep 1	
done
