#!/bin/bash
echo "entering $0"
[ "${1}" = 'bash' -o "$1" = "/bin/bash" ] && bash && exit 0


export REDIS_PIDFILE=/var/run/redis/redis-server.pid
export MYSQLD_PIDFILE=/var/run/mysqld/mysqld.pid
export FRITZ_PIDFILE=/var/run/fritzdump.pid

function prepare_sql()
{
	#prepare mariadb
	chown -R mysql:mysql "${MYSQL_ROOT}"
	gosu mysql /mariadb-entrypoint.sh prepare mysqld
}

function start()
{
	# start services in background here
	/etc/init.d/redis-server start 
	start-stop-daemon --start -b --quiet --oknodo --pidfile "${MYSQLD_PIDFILE}" --chuid mysql:mysql --exec /mariadb-entrypoint.sh -- mysqld
	for i in 1 1 1 2 5; do
		echo 'show schemas;' |  mysql --user=$MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE &>/dev/null
		[ "$?" = 0 ] && break;
	done

	# run the main thing
	chown -R ntopng "${NTOPNG_DATA}"
	/fritzdump/fritzdump.sh "$@" &
	FRITZ_PID=$!
	echo "$FRITZ_PID" > "${FRITZ_PIDFILE}"
}

function stopall()
{
	FRITZ_PID=$(cat "$FRITZ_PIDFILE")
	if [ -n "${FRITZ_PID}" ]; then
	#FRITZ_GPID=$(cat /proc/$(cat $FRITZ_PIDFILE)/stat | cut -d ' ' -f 5)
		for i in 20 20; do
			kill -s TERM -- $FRITZ_PID &>/dev/null
			sleep 10
			kill -0 -- $FRITZ_PID &>/dev/null || break
			sleep $i
		done

		kill -9 -- $FRITZ_PID &>/dev/null
		rm -rf "${FRITZ_PIDFILE}" &>/dev/null
	fi

	start-stop-daemon --stop --retry forever/TERM/1 --quiet --oknodo --pidfile ${MYSQLD_PIDFILE} --name mysqld
	start-stop-daemon --stop --retry forever/TERM/1 --quiet --oknodo --pidfile ${REDIS_PIDFILE} --name redis-server
}
export -f stopall

prepare_sql
start

# TODO: this still won't get propagated to ntopng
trap "echo $0: TRAPed signal, terminating...; stopall;" HUP INT QUIT TERM

wait
stopall

echo "exited $0"
