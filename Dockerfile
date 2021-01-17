FROM debian:buster-slim

# mysql stuff install

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mysql && useradd -r -g mysql mysql

RUN apt-get update && \
    apt-get -y install curl gosu software-properties-common gnupg2 && \
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xF1656F24C74CD1D8 && \
    add-apt-repository 'deb http://mariadb.mirror.liquidtelecom.com/repo/10.4/debian buster main' && \
    curl -sO https://packages.ntop.org/apt-stable/buster/all/apt-ntop-stable.deb && \
    dpkg -i ./apt-ntop-stable.deb && \
    rm ./apt-ntop-stable.deb && \
    touch /.dockerenv && \
    ln -s /dev/null /etc/systemd/system/ntopng.service && \
    gosu nobody true && \
    apt-get update && \
    apt-get -y install socat pfring pfring-dkms ntopng mariadb-server mariadb-backup && \
    apt-get clean all && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /docker-entrypoint-initdb.d

RUN set -ex; \
# comment out any "user" entires in the MySQL config ("docker-entrypoint.sh" or "--user" will handle user switching)
  sed -ri 's/^user\s/#&/' /etc/mysql/my.cnf /etc/mysql/conf.d/*; \
# purge and re-create /var/lib/mysql with appropriate ownership
  rm -rf /var/lib/mysql; \
  mkdir -p /var/lib/mysql /var/run/mysqld; \
  chown -R mysql:mysql /var/lib/mysql /var/run/mysqld; \
# ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
  chmod 777 /var/run/mysqld; \
# comment out a few problematic configuration values
  find /etc/mysql/ -name '*.cnf' -print0 \
    | xargs -0 grep -lZE '^(bind-address|log)' \
    | xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/'; \
# don't reverse lookup hostnames, they are usually another container
  echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf

VOLUME /var/lib/mysql

# end of generic mysql install

# which ports to provide out - needs to be used in docker run -p to be actually published
# EXPOSE 3306/tcp

ADD ["mariadb-entrypoint.sh", "/usr/local/bin/"]
RUN chmod +x /usr/local/bin/mariadb-entrypoint.sh && \
    ln -s /usr/local/bin/mariadb-entrypoint.sh /

# end of mariadb

# our config

ENV NTOPNG_PORT=80

ENV NTOPNG_DATA=/fritzdump/data
ENV FRITZIP=http://fritz.box
ENV FRITZUSER=admin
ENV FRITZPWD=admin
ENV IFACE="1-lan"
ENV LOCALNETS=""
ENV INSTANCE_NAME="docker"
# ENV IGNORE_HOSTS="not ip host 192.168.0.254 and not ip host 192.168.0.134"

ENV MYSQL_DATABASE="fritzdump"
ENV MYSQL_USER="ntopng"
ENV MYSQL_PASSWORD="ntopng"
ENV MYSQL_ROOT_PASSWD="changeme, dummy!"

# which ports to provide out - needs to be used in docker run -p to be actually published
EXPOSE ${NTOPNG_PORT}/tcp

RUN mkdir /fritzdump
ADD ["fritzdump.sh", "/fritzdump"]
RUN chmod +x /fritzdump/fritzdump.sh

RUN mkdir -p "${NTOPNG_DATA}" && chown ntopng "${NTOPNG_DATA}"
VOLUME "${NTOPNG_DATA}"

ADD ["entrypoint.sh", "/"]
RUN chmod +x "/entrypoint.sh"

STOPSIGNAL SIGINT

ENTRYPOINT ["/entrypoint.sh"]
