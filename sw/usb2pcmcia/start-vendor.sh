#!/bin/sh
set -eu

service_dir=/media/fat/linux/pc110-pcmcia
runtime_home=/tmp/pc110-pcmcia-home

# The vendor enumerator requires /home/p, while MiSTer's root filesystem is
# normally read-only. Test the operation itself because root's access check can
# still report a read-only directory as writable. Preserve the existing /home
# contents in RAM only when the directory cannot be created in place.
if ! mkdir -p /home/p 2>/dev/null; then
	mkdir -p "${runtime_home}"
	cp -a /home/. "${runtime_home}/" 2>/dev/null || true
	mkdir -p "${runtime_home}/p"
	mount --bind "${runtime_home}" /home
fi
mkdir -p /home/p
chmod 700 /home/p

# A forced stop can leave this transient IPC file behind. Vendor releases use
# either /home/p or /home/ftp for the shared page; a stale copy prevents the
# next launch from initializing.
rm -f /home/p/arstech /home/ftp/arstech

cd "${service_dir}"
if [ -x ./arsenum4-cis-inject ]; then
	exec ./arsenum4-cis-inject ./arsenum4
fi
exec ./arsenum4
