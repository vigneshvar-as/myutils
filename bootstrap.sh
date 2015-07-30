#!/bin/bash

CONSULURL=$1
TOKEN=$2
CONSUL_DIR=/tmp/consul/
RUNONCE=/usr/bin/runonce

mkdir -p  $CONSUL_DIR
mkdir -p  $CONSUL_DIR/data

curl $CONSULURL -o $CONSUL_DIR/consul
chmod 777 $CONSUL_DIR/consul

IP=`ip addr | grep inet | grep -v "::" | grep -v "127.0.0.1" | awk {'print $2'} | cut -d"/" -f 1`
if [ "$IP" == "" ]
then
	echo "Error cannot determine IP. Exiting ..." > /var/log/consul.log
	exit
fi

#TOKEN=`curl $TOKENURL`
echo "{\"encrypt\": \"$TOKEN\"}" > /etc/enc.json

cat << EOF > $RUNONCE
#!/bin/bash

if [ "\$#" -eq 0 ]
then
        echo "Pass parameter"
        exit
fi
cmd="\$*"

process=\`ps aux | grep -w "\$cmd" | grep -v "grep" | grep -v "runonce" | wc -l\`
if [ \$process -eq 0 ]
then
        echo "Excuting cmd"
        \$cmd
fi

EOF

chmod 777 $RUNONCE

CRON_STATE=`crontab -l | grep -i consul | wc -l`
if [ $CRON_STATE -ne 1 ]
then
	ROLE=`cat /var/run/role`

	if [ "$ROLE" == "server" ]
	then
		#./consul agent -server -data-dir data/ -bind 15.1.0.8 -bootstrap-expect 1
                echo "* * * * * $RUNONCE $CONSUL_DIR/consul agent -server -bootstrap-expect 1 -data-dir $CONSUL_DIR/data -config-file /etc/enc.json  -bind $IP >> /var/log/consul.log 2>&1 &" > /tmp/cmd
	
	else
                echo "* * * * * $RUNONCE $CONSUL_DIR/consul agent -data-dir $CONSUL_DIR/data -config-file /etc/enc.json  -bind $IP >> /var/log/consul.log 2>&1 &" > /tmp/cmd
	fi
	crontab < /tmp/cmd
fi

