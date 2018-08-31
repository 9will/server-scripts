#!/bin/bash
# This script downloads the latest version of dnscrypt-proxy automatically
# TODO: to support distributions other than Debian & Ubuntu
# TODO: to add --verbose and --help

function ask_yn() {
	declare ans=
	while true; do
		echo -n $@ "(y/n) "
		read ans
		[ "$ans" = "y" ] && return 0
		[ "$ans" = "Y" ] && return 0
		[ "$ans" = "n" ] && return 1
		[ "$ans" = "N" ] && return 1
		[ "$ans" ] && echo "Not understood answer: $ans" >&2
	done
}

function ask_Yn() {
	declare ans=
	while true; do
		echo -n $@ "(Y/n) "
		read ans
		[ "$ans" ] || return 0
		[ "$ans" = "y" ] && return 0
		[ "$ans" = "Y" ] && return 0
		[ "$ans" = "n" ] && return 1
		[ "$ans" = "N" ] && return 1
		echo "Not understood answer: $ans" >&2
	done
}

function ask_yN() {
	declare ans=
	while true; do
		echo -n $@ "(y/N) "
		read ans
		[ "$ans" ] || return 1
		[ "$ans" = "y" ] && return 0
		[ "$ans" = "Y" ] && return 0
		[ "$ans" = "n" ] && return 1
		[ "$ans" = "N" ] && return 1
		echo "Not understood answer: $ans" >&2
	done
}

function die() {
	echo -e "ERROR: $@" >&2
	exit 1
}

function complain() {
	echo -e "WARNING: $@" >&2
}

function clean() {
	rm -f "$DNSCRYPT_FILENAME" "$RELEASE_FILENAME"
}

function clean_and_exit() {
	echo "Well well. Give me some time to clean it up..." >&2
	rm -f "DNSCRYPT_FILENAME" "$RELEASE_FILENAME"
}

function instpkg() {
	apt-get --yes install $@
}

function rmpkg() {
	apt-get --yes remove $@
}

function haspkg() {
	[ $# -gt 1 ] && die "too many arguments to haspkg."
	[ $# -lt 1 ] && die "too few arguments to haspkg."
	dpkg -l | grep $1 &> /dev/null
	return $?
}

function parse() {
	# TODO: stub
	:
}

function help() {
	# TODO: stub
	:
}

function download() {
	cd /var/tmp
	curl --version || instpkg curl || die "Failed to install curl."
	jq --version || instpkg jq || die "Failed to install jq."
	echo "Checking for the latest release of dnscrypt-proxy..."
	RELEASE_FILENAME=dnscrypt-proxy-releases-${RANDOM}.json
	curl https://api.github.com/repos/jedisct1/dnscrypt-proxy/releases > "$RELEASE_FILENAME" || die "Failed to check for the latest release."
	URL_TO_DNSCRYPT="$(cat $RELEASE_FILENAME | jq .\[0\] | grep download | grep -v minisig | grep linux_x86_64 | cut -d : -f2- | tr -d \")"
	DNSCRYPT_FILENAME="$(echo "$URL_TO_DNSCRYPT" | rev | cut -d / -f1 | rev)"
	wget --output-document="$DNSCRYPT_FILENAME" $URL_TO_DNSCRYPT || die "Downloading $URL_TO_DNSCRYPT failed."
}

function extract() {
	tar zxvf "$DNSCRYPT_FILENAME" -C /usr/bin linux-x86_64/dnscrypt-proxy --strip-components=1
	if [ -a "/etc/dnscrypt-proxy.toml" ]; then
		[ -f "/etc/dnscrypt-proxy.toml" ] || die "/etc/dnscrypt-proxy.toml exists but is not a regular file. Why?"
		echo "/etc/dnscrypt-proxy.toml already exists. Decided not to touch it."
	else
		tar zxvf "$DNSCRYPT_FILENAME" linux-x86_64/example-dnscrypt-proxy.toml -O | awk -F '# ' '{ if ($0 ~ "server_names = ") print $2; else print $0; }' > /etc/dnscrypt-proxy.toml || die "Failed to write to /etc/dnscrypt-proxy.toml..."
	fi
}

function install() {
	if haspkg resolvconf; then
		echo "resolvconf detected. Trying to remove it..."
		rmpkg resolvconf || die "resolvconf couldn't be removed."
	fi
	if haspkg dnscrypt-proxy; then
		echo "PM-installed dnscrypt-proxy detected. Trying to remove it..."
		rmpkg dnscrypt-proxy || die "PM-installed dnscrypt-proxy couldn't be removed."
		rm -f /{etc,lib}/systemd/system/dnscrypt-proxy.{service,socket}
	fi
	echo "Stopping and disabling systemd-resolved..."
	systemctl stop systemd-resolved || die "Failed to stop systemd-resolved."
	systemctl disable systemd-resolved || die "Failed to disable systemd-resolved..."
	RESOLVCONF_BAK=/etc/resolv.conf.bak-${RANDOM}
	echo "Backuping /etc/resolv.conf to $RESOLVCONF_BAK and creating a new one..."
	cp /etc/resolv.conf "$RESOLVCONF_BAK" || die "Failed to backup resolv.conf..."
	echo -e "nameserver 127.0.0.1\\noptions edns0 single-request-reopen" > /etc/resolv.conf
	echo "Installing the service and starting it..."
	cd /etc
	dnscrypt-proxy -config /etc/dnscrypt-proxy.toml -service install || die "Failed to install the service."
	cd -
	systemctl start dnscrypt-proxy || die "Failed to start the service."
	systemctl enable dnscrypt-proxy || die "Failed to enable the service."
}

function welldone() {
	echo "Successfully installed dnscrypt-proxy onto your system."
	echo "Note that /etc/resolv.conf is overwritten by many dhcp clients on startup. You can make it immutable using the following command:"
	echo
	echo -e "\\tchattr +i /etc/resolv.conf"
	echo
	echo "Be careful because this causes problems with some of them; see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=860928."
	echo "Good luck!"
}

ask_yN "Do you want to install dnscrypt-proxy?"
trap 'clean_and_exit' INT
parse
download
extract
install
clean
welldone

