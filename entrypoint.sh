#!/bin/sh
echo "entering $0"
[ "${1}" = 'bash' ] && bash && exit 0


REDIS_PIDFILE=/var/run/redis/redis-server.pid
MYSQLD_PIDFILE=/var/run/mysqld/mysqld.pid
#prepare mariadb
gosu mysql /mariadb-entrypoint.sh prepare mysqld

# start services in background here
/etc/init.d/redis-server start 
start-stop-daemon --start -b --quiet --oknodo --pidfile "${MYSQLD_PIDFILE}" --chuid mysql:mysql --exec /mariadb-entrypoint.sh -- mysqld

# run the main thing TODO: trap seems not to work :-(
trap "echo TRAPed signal" HUP INT QUIT TERM
/fritzdump/fritzdump.sh "$@"

start-stop-daemon --stop --retry forever/TERM/1 --quiet --oknodo --pidfile ${MYSQLD_PIDFILE} --name mysqld
start-stop-daemon --stop --retry forever/TERM/1 --quiet --oknodo --pidfile ${REDIS_PIDFILE} --name redis-server


echo "exited $0"
