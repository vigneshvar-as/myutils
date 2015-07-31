#!/bin/bash

CONSULURL=$1
TOKEN=$2
JSAWK_URL=$3
TOTAL=$4
REPOURL=$5
NAME=$6
MEM=$7
HEAP=$8

CONSUL_DIR=/opt/consul/
RUNONCE=/usr/bin/runonce

mkdir -p  $CONSUL_DIR
mkdir -p  $CONSUL_DIR/data

curl $CONSULURL -o $CONSUL_DIR/consul
chmod 777 $CONSUL_DIR/consul

curl $JSAWK_URL -o /usr/bin/jsawk
chmod 777 /usr/bin/jsawk
yum -y install js-devel

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
		crontab < /tmp/cmd

		join=1
                count=1
                sleep 10
                while [ $join -eq 1 ]
                do
                        join=`$CONSUL_DIR/consul members | grep  "connection refused" | wc -l`
                        count=`expr $count + 1`
                        sleep 1
                        if [ $count -eq 500 ]
                        then
                                echo "consul failed to start"
                                exit
                        fi
                done
		# Add data to consul from server
		sleep 40
		curl -X PUT -d "$TOTAL"  http://localhost:8500/v1/kv/cassandra/node_count
		curl -X PUT -d "$REPOURL/cassandra-bootstrap.sh" http://localhost:8500/v1/kv/role/cassandra

	else
                echo "* * * * * $RUNONCE $CONSUL_DIR/consul agent -data-dir $CONSUL_DIR/data -config-file /etc/enc.json  -bind $IP >> /var/log/consul.log 2>&1 &" > /tmp/cmd
		masterip=`curl http://169.254.169.254/openstack/2013-10-17/meta_data.json  | jsawk 'return this.meta.consul_master'`
		crontab < /tmp/cmd
		join=1
		count=1
		sleep 10
		while [ $join -eq 1 ]
		do
			join=`$CONSUL_DIR/consul join $masterip | grep  "connection refused" | wc -l`
			count=`expr $count + 1`
			sleep 1
			if [ $count -eq 500 ]
			then
				echo "master join failed"
				exit
			fi
		done
		join=""
                count=1
                sleep 10
                while [ "$join" == "" ]
                do
                        join=`curl http://localhost:8500/v1/kv/role/$ROLE?raw`
                        count=`expr $count + 1`
                        sleep 1
                        if [ $count -eq 500 ]
                        then
                                echo "Did not get role bootstrap"
                                exit
                        fi
                done
		cd /opt/
		curl $join -o role-bootstrap.sh
		sh -x role-bootstrap.sh $NAME $REPOURL $MEM $HEAP

	fi
#	crontab < /tmp/cmd
fi

