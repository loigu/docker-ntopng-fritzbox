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
NTOPNG_DATA="${NTOPNG_DATA:-./data}"

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

echo "Trying to login into $FRITZIP as user $FRITZUSER"


# Request challenge token from Fritz!Box
CHALLENGE=$(curl -k -s $FRITZIP/login_sid.lua |  grep -o "<Challenge>[a-z0-9]\{8\}" | cut -d'>' -f 2)

# Very proprieatry way of AVM: Create a authentication token by hashing challenge token with password
HASH=$(perl -MPOSIX -e '
    use Digest::MD5 "md5_hex";
    my $ch_Pw = "$ARGV[0]-$ARGV[1]";
    $ch_Pw =~ s/(.)/$1 . chr(0)/eg;
    my $md5 = lc(md5_hex($ch_Pw));
    print $md5;
  ' -- "$CHALLENGE" "$FRITZPWD")
  
# TODO: can we use wget here?
SID="$(curl -k -s "$FRITZIP/login_sid.lua" -d "response=$CHALLENGE-$HASH" -d 'username='${FRITZUSER} 2>/dev/null | grep -o "<SID>[a-z0-9]\{16\}" | cut -d'>' -f 2)"

# Check for successfull authentification
if [[ $SID =~ ^0+$ ]] ; then echo "Login failed. Did you create & use explicit Fritz!Box users?" ; exit 1 ; fi

echo "Capturing traffic on Fritz!Box interface $IFACE ..." 1>&2

DATADIR="$(dirname $0)/data/ntopng-$IFACE.data"
[ ! -d "${DATADIR}" ] && mkdir -p "${DATADIR}"

# TODO: trap seems not to work :-(
trap "echo TRAPed signal" HUP INT QUIT TERM
wget --no-check-certificate -qO- $FRITZIP/cgi-bin/capture_notimeout?ifaceorminor=$IFACE\&snaplen=\&capture=Start\&sid=$SID  |\
    ntopng -U ntopng -i - -n 1 -w "${NTOPNG_PORT}" -W 0 -n 1 -d "${NTOPNG_DATA}" ${EXTRA}

