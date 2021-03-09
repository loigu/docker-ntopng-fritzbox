#!/bin/bash

FRITZCONF=$(dirname "$0")/fritzdump.conf

[ -n "${1}" ] && FRITZCONF="$1"
[ -f "${FRITZCONF}" ] && . "${FRITZCONF}"


if [ -z "${FRITZIP}" -o -z "${FRITZUSER}" -o -z "${FRITZPWD}" ]; then
	echo "create ${FRITZCONF} from fritzdump.conf.example and pass in"
	exit 1
fi

# "internet"
# IFACE="3-17"
# IFACE="1-eth0"

# Lan Interface
IFACE="${IFACE:-1-lan}"
NTOPNG_PORT="${NTOPNG_PORT:-8000}"
NTOPNG_DATA="${NTOPNG_DATA:-$(dirname $BASH_SOURCE)/data/ntopng-$IFACE.data}"
[ ! -d "${NTOPNG_DATA}" ] && mkdir -p "${NTOPNG_DATA}"

EXTRA=""
[ -n "${INSTANCE_NAME}" ] && EXTRA="${EXTRA} -N ${INSTANCE_NAME}"
[ -n "${LOCALNETS}" ] && EXTRA="${EXTRA} -m ${LOCALNETS}"
[ -n "${IGNORE_HOSTS}" ] && EXTRA="${EXTRA} -B ${IGNORE_HOSTS}"

if [ -n "${MYSQL_DATABASE}" -a -n "${MYSQL_USER}" -a -n "${MYSQL_PASSWORD}" ]; then
    echo "storing data to mysql db ${MYSQL_DATABASE}"
    EXTRA="${EXTRA} -F mysql;localhost;${MYSQL_DATABASE};dummy;${MYSQL_USER};${MYSQL_PASSWORD}"
else
    echo "no mysql db passed, no persistence"
fi

CURL_PIDFILE="/var/run/curl.pid"
NTOPNG_PIDFILE="/var/run/ntopng.pid"


function run_capture()
{
	echo "Trying to login into $FRITZIP as user $FRITZUSER"


	# Request challenge token from Fritz!Box
	CHALLENGE=$(curl -k -s $FRITZIP/login_sid.lua --connect-timeout 15 |  grep -o "<Challenge>[a-z0-9]\{8\}" | cut -d'>' -f 2)
	[ -z "${CHALLENGE}" ] && echo "no challenge from fritzbox" >&2 && return 1

	# Very proprieatry way of AVM: Create a authentication token by hashing challenge token with password
	HASH=$(perl -MPOSIX -e '
	    use Digest::MD5 "md5_hex";
	    my $ch_Pw = "$ARGV[0]-$ARGV[1]";
	    $ch_Pw =~ s/(.)/$1 . chr(0)/eg;
	    my $md5 = lc(md5_hex($ch_Pw));
	    print $md5;
	  ' -- "$CHALLENGE" "$FRITZPWD")
	  
	SID=$(curl -k -s "$FRITZIP/login_sid.lua" --connect-timeout 15 -d "response=$CHALLENGE-$HASH" -d "username=${FRITZUSER}" 2>/dev/null | grep -o "<SID>[a-z0-9]\{16\}" | cut -d'>' -f 2)

	# Check for successfull authentification
	if [[ "$SID" =~ ^0+$ ]] || [ -z "$SID" ] ; then echo "Login failed. Did you create & use explicit Fritz!Box users?" >&2 ; return 1; fi

	echo "Capturing traffic on Fritz!Box interface $IFACE ..." 1>&2
	(/usr/bin/curl -sk -o - "$FRITZIP/cgi-bin/capture_notimeout?ifaceorminor=$IFACE&snaplen=&capture=Start&sid=$SID" | \
		/usr/bin/ntopng -U ntopng -i - -n 1 -w "${NTOPNG_PORT}" -W 0 -n 1 -d "${NTOPNG_DATA}" ${EXTRA}) &

	pgrep -lf /usr/bin/ntopng | cut -d ' ' -f 1 > "${NTOPNG_PIDFILE}"
	pgrep -lf /usr/bin/curl | cut -d ' ' -f 1 > "${CURL_PIDFILE}"

	kill -0 $(cat "${NTOPNG_PIDFILE}") || return 1
	kill -0 $(cat "${CURL_PIDFILE}") || return 1
}

function stop_curl()
{
	echo "stopping curl" >&2
	# nothing to do
	[ ! -f "${CURL_PIDFILE}" ] && return 0
	pid=$(cat "${CURL_PIDFILE}")

	# try softly
	for i in 1 1 1 2 5; do
		kill -0 $pid &>/dev/null || break
		kill -TERM $pid &>/dev/null
		sleep $i
	done

	# force cleanup
	kill -9 $pid &>/dev/null 
	kill -0 "$pid" &>/dev/null || rm -f "${CURL_PIDFILE}" &>/dev/null
}
export -f stop_curl

function stop_ntopng()
{
	echo "stopping ntopng" >&2

	[ ! -f "${NTOPNG_PIDFILE}" ] && return 0
	pid=$(cat "${NTOPNG_PIDFILE}")

	# ntopng requires time to finish writing data, second TERM quits the writeback
	for i in 20 20; do
		kill -0 $pid &>/dev/null || break
		kill -TERM $pid &>/dev/null
		sleep 5
		kill -0 $pid &>/dev/null || break
		sleep $i
	done

	# force cleanup
	kill -9 $pid &>/dev/null 
	kill -0 "$pid" &>/dev/null || rm -f "${NTOPNG_PIDFILE}" &>/dev/null
}
export -f stop_ntopng

function stop_capture()
{
	stop_curl
	stop_ntopng
}
export -f stop_capture

DIE_MARK=/var/run/die

function watchdog()
{
	# check & restart reading
	for i in 1 2 2 5 50 60 60 30 30 30 30; do
		[ -f "${DIE_MARK}" ] && return 0
		[ -f "${CURL_PIDFILE}" ] && kill -0 $(cat "${CURL_PIDFILE}") &>/dev/null && \
			[ -f "${NTOPNG_PIDFILE}" ] && kill -0 $(cat "${NTOPNG_PIDFILE}") &>/dev/null && break

		stop_capture
		run_capture || stop_capture

		sleep $i
	done
}

function stopall()
{
	touch "${DIE_MARK}"

	# stop capture
	stop_capture

	# remove pipe
	[ -p "${PIPE}" ] && rm "${PIPE}" 
}
export -f stopall

trap "echo $0: signal trapped, exiting...; stopall;" TERM INT HUP QUIT

rm "${DIE_MARK}" &>/dev/null
run_capture || stop_capture

while [ ! -f "${DIE_MARK}" ]; do
	sleep 5
	watchdog
done

stopall

