#!/bin/bash
# Download cassandra tar
# Download cassandra yaml
# Download cassandra sh
# Download cassandra service

# Check if its ip is added to nodes key in consul
# If not added kindly add it

# Check the total number of nodes from consul equal to number of nodes in key
# if yes 
#	configure cassandra yaml
#	configure cassandra sh
#	enable service
# If not loop it back  and wait till times out
# If times out update error key on consul as failed

CLUSTERNAME=$1
REPOURL=$2
MEM=$3
HEAP=$4


curl $REPOURL/cassandra.tar -o /opt/cassandra.tar
curl $REPOURL/cassandra.yaml -o /opt/cassandra.yaml
curl $REPOURL/cassandra.sh -o /opt/cassandra.sh
curl $REPOURL/cassandra.service -o /opt/cassandra.service
curl $REPOURL/jdk-7u79-linux-x64 -o /opt/jdk-7u79-linux-x64

cd /opt/
tar xf cassandra.tar
cp /opt/cassandra.yaml /opt/cassandra/conf/
cp /opt/cassandra.sh /opt/cassandra/conf/
cp /opt/cassandra.service /etc/systemd/system/

status=`cat /etc/profile | grep JAVA_HOME | wc -l`

if [ $status -eq 0 ]
then
	tar xf jdk-7u79-linux-x64
	echo "export JAVA_HOME=/opt/jdk1.7.0_79/" >> /etc/profile
	echo "export PATH=\"\$PATH:\$JAVA_HOME/bin/\"" >> /etc/profile
	ln -s /opt/jdk1.7.0_79/bin/java /usr/bin/java
fi


IP=`ip addr | grep inet | grep -v "::" | grep -v "127.0.0.1" | awk {'print $2'} | cut -d"/" -f 1`
if [ "$IP" == "" ]
then
        echo "Error cannot determine IP. Exiting ..." > /var/log/consul.log
        exit
fi



added=`curl http://localhost:8500/v1/kv/cassandra/seed?raw | grep "$IP" | wc -l`
if [ $added -eq 0 ]
then
        tmp=`curl http://localhost:8500/v1/kv/cassandra/seed?raw`
        if [ "$tmp" == "" ]
        then
                curl -X PUT -d "$IP" http://localhost:8500/v1/kv/cassandra/seed?raw
        else
                curl -X PUT -d "$tmp,$IP" http://localhost:8500/v1/kv/cassandra/seed?raw
        fi
fi

sleep 20
added=`curl http://localhost:8500/v1/kv/cassandra/seed?raw | grep "$IP" | wc -l`
if [ $added -eq 0 ]
then
        tmp=`curl http://localhost:8500/v1/kv/cassandra/seed?raw`
        if [ "$tmp" == "" ]
        then
                curl -X PUT -d "$IP" http://localhost:8500/v1/kv/cassandra/seed?raw
        else
                curl -X PUT -d "$tmp,$IP" http://localhost:8500/v1/kv/cassandra/seed?raw
        fi
fi





# Check with consul
data=""
while [ "$data" == "" ]
do
	data=`curl http://localhost:8500/v1/kv/cassandra/node_count?raw`
	#compare
	# check if seed is empty
	# check if seed has one entry
	# check the number of entries
	if [ "$data" != "" ]
	then
		SEED=`curl http://localhost:8500/v1/kv/cassandra/seed?raw`
		if [ "$SEED" != "" ]
		then
			nodes_reg=`echo $SEED | grep -o "," | wc -l`
			nodes_reg=`expr $nodes_reg + 1`
			if [ $data -ne $nodes_reg ]
			then
				data=""
			fi
		else
			data=""
		fi
	fi
	sleep 3
done



# Configure 
sed -i "s/<cluster>/$CLUSTERNAME/g"  /opt/cassandra/conf/cassandra.yaml
sed -i "s/<seed>/$SEED/g"  /opt/cassandra/conf/cassandra.yaml
sed -i "s/<ip>/$IP/g" /opt/cassandra/conf/cassandra.yaml

sed -i "s/<MEM>/$MEM/g"  /opt/cassandra/conf/cassandra-env.sh
sed -i "s/<HEAP>/$HEAP/g"  /opt/cassandra/conf/cassandra-env.sh


source /etc/profile
systemctl enable cassandra
service cassandra restart

