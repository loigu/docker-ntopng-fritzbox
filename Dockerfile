FROM debian:buster-slim

# mysql stuff install

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mysql && useradd -r -g mysql mysql

# add gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.12
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

RUN mkdir /docker-entrypoint-initdb.d

ENV GPG_KEYS \
# pub   rsa4096 2016-03-30 [SC]
#         177F 4010 FE56 CA33 3630  0305 F165 6F24 C74C D1D8
# uid           [ unknown] MariaDB Signing Key <signing-key@mariadb.org>
# sub   rsa4096 2016-03-30 [E]
	177F4010FE56CA3336300305F1656F24C74CD1D8
RUN set -ex; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in $GPG_KEYS; do \
		gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done; \
	gpg --batch --export $GPG_KEYS > /etc/apt/trusted.gpg.d/mariadb.gpg; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -r "$GNUPGHOME"; \
	apt-key list

# bashbrew-architectures: amd64 arm64v8 ppc64le
ENV MARIADB_MAJOR 10.3
ENV MARIADB_VERSION 1:10.3.22+maria~buster
# release-status:Stable
# (https://downloads.mariadb.org/mariadb/+releases/)

RUN set -e;\
	echo "deb http://ftp.osuosl.org/pub/mariadb/repo/$MARIADB_MAJOR/debian buster main" > /etc/apt/sources.list.d/mariadb.list; \
	{ \
		echo 'Package: *'; \
		echo 'Pin: release o=MariaDB'; \
		echo 'Pin-Priority: 999'; \
	} > /etc/apt/preferences.d/mariadb
# add repository pinning to make sure dependencies from this MariaDB repo are preferred over Debian dependencies
#  libmariadbclient18 : Depends: libmysqlclient18 (= 5.5.42+maria-1~wheezy) but 5.5.43-0+deb7u1 is to be installed

# the "/var/lib/mysql" stuff here is because the mysql-server postinst doesn't have an explicit way to disable the mysql_install_db codepath besides having a database already "configured" (ie, stuff in /var/lib/mysql/mysql)
# also, we set debconf keys to make APT a little quieter
RUN set -ex; \
	{ \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password password 'unused'; \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password_again password 'unused'; \
	} | debconf-set-selections; \
	apt-get update; \
	apt-get install -y \
		"mariadb-server=$MARIADB_VERSION" \
# mariadb-backup is installed at the same time so that `mysql-common` is only installed once from just mariadb repos
		mariadb-backup \
		socat \
	; \
	rm -rf /var/lib/apt/lists/*; \
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
RUN chmod +x /usr/local/bin/mariadb-entrypoint.sh
RUN ln -s /usr/local/bin/mariadb-entrypoint.sh /

# end of mariadb
# beginning of ntopng

RUN wget -q http://packages.ntop.org/apt-stable/buster/all/apt-ntop-stable.deb && \
    dpkg -i apt-ntop-stable.deb && \
    apt-get clean all

RUN apt-get update && \
    apt-get -y install ntopng curl
#    apt-get clean all && \\
#    rm -rf /var/lib/apt/lists/*

# end ntopng install

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
