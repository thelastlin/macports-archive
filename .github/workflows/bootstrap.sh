#!/bin/bash
# Source: https://github.com/macports/macports-ci-files
set -e

MPBB=$1

printtag() {
    # GitHub Actions tag format
    echo "::$1::${2-}"
}

begingroup() {
    printtag "group" "$1"
}

endgroup() {
    printtag "endgroup"
}

MACPORTS_VERSION=${MP_CI_RELEASE:-2.11.6}

OS_MAJOR=$(uname -r | cut -f 1 -d .)
OS_ARCH=$(uname -m)
case "$OS_ARCH" in
    i586|i686|x86_64)
        OS_ARCH=i386
        ;;
    arm64)
        OS_ARCH=arm
        ;;
esac

MACPORTS_FILENAME=MacPorts-${MACPORTS_VERSION}-${OS_MAJOR}.tar.bz2

begingroup "Fetching files"
# Download resources in background ASAP but use later.
# Use /usr/bin/curl so that we don't use Homebrew curl.
echo "Fetching MacPorts..."
/usr/bin/curl -fsSLO "https://github.com/thelastlin/macports-ci-files/releases/download/v${MACPORTS_VERSION}/${MACPORTS_FILENAME}" &
curl_mpbase_pid=$!
echo "Fetching getopt..."
/usr/bin/curl -fsSLO "https://distfiles.macports.org/_ci/getopt/getopt-v1.1.6.tar.bz2" &
curl_getopt_pid=$!
if [ -n "$MPBB" ] ; then
PORTINDEX_URL="https://ftp.fau.de/macports/release/ports/PortIndex_darwin_${OS_MAJOR}_${OS_ARCH}/PortIndex"
echo "Fetching PortIndex from $PORTINDEX_URL ..."
/usr/bin/curl -fsSLo ports/PortIndex "$PORTINDEX_URL" &
curl_portindex_pid=$!
fi
endgroup


begingroup "Disabling Spotlight"
# Disable Spotlight indexing. We don't need it, and it might cost performance
sudo mdutil -a -i off
endgroup


begingroup "Uninstalling Homebrew"
# Move directories to /opt/*-off
echo "Moving directories..."
sudo mkdir /opt/local-off /opt/homebrew-off
test ! -d /usr/local || /usr/bin/sudo /usr/bin/find /usr/local -mindepth 1 -maxdepth 1 -type d -print -exec /bin/mv {} /opt/local-off/ \;
test ! -d /opt/homebrew || /usr/bin/sudo /usr/bin/find /opt/homebrew -mindepth 1 -maxdepth 1 -type d -print -exec /bin/mv {} /opt/homebrew-off/ \;

# Unlink files
echo "Removing files..."
test ! -d /usr/local || /usr/bin/sudo /usr/bin/find /usr/local -mindepth 1 -maxdepth 1 -type f -print -delete
test ! -d /opt/homebrew || /usr/bin/sudo /usr/bin/find /opt/homebrew -mindepth 1 -maxdepth 1 -type f -print -delete

# Rehash to forget about the deleted files
hash -r
endgroup

begingroup "Selecting Xcode version"
case "$OS_MAJOR" in
    22) sudo xcode-select --switch /Applications/Xcode_14.3.1.app/Contents/Developer
        ;;
    23) sudo xcode-select --switch /Applications/Xcode_15.4.app/Contents/Developer
        ;;
esac
endgroup

begingroup "Installing getopt"
# Install getopt required by mpbb
if ! wait $curl_getopt_pid; then
    echo "Fetching getopt failed: $?"
fi
echo "Extracting..."
sudo tar -xpf "getopt-v1.1.6.tar.bz2" -C /
rm -f "getopt-v1.1.6.tar.bz2"
endgroup


begingroup "Installing MacPorts"
# Install MacPorts built by github.com:thelastlin/macports-ci-files
if ! wait $curl_mpbase_pid; then
    echo "Fetching base failed: $?"
fi
echo "Extracting..."
sudo tar -xpf "${MACPORTS_FILENAME}" -C /
rm -f "${MACPORTS_FILENAME}"
endgroup


begingroup "Configuring MacPorts"
# Set PATH for portindex
source /opt/port/share/macports/setupenv.bash
# Set ports tree to $PWD/ports
echo "file://${PWD}/ports [default,nosync]" | sudo tee /opt/port/etc/macports/sources.conf >/dev/null
# CI is not interactive
echo "ui_interactive no" | sudo tee -a /opt/port/etc/macports/macports.conf >/dev/null
# Only download from the CDN, not the mirrors
echo "host_blacklist *.distfiles.macports.org *.packages.macports.org" | sudo tee -a /opt/port/etc/macports/macports.conf >/dev/null
# Prefer hosts close to github
echo "preferred_hosts mirror.fcix.net github.com *.github.com" | sudo tee -a /opt/port/etc/macports/macports.conf >/dev/null
#We don't have permission to the private server
# Also try downloading archives from the private server
# echo "archive_site_local https://packages-private.macports.org/:tbz2" | sudo tee -a /opt/port/etc/macports/macports.conf >/dev/null
# Prefer to get archives from the public server instead of the private server
# preferred_hosts has no effect on archive_site_local
# See https://trac.macports.org/ticket/57720
#echo "preferred_hosts packages.macports.org" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
endgroup


# Do not update PortIndex at here

if false; then

if [ -n "$MPBB" ] ; then
begingroup "Updating PortIndex"
## Run portindex on recent commits if PR is newer
git -C ports/ remote add macports https://github.com/macports/macports-ports.git
git -C ports/ fetch macports master
git -C ports/ checkout -qf macports/master~10
git -C ports/ checkout -qf -
git -C ports/ checkout -qf "$(git -C ports/ merge-base macports/master HEAD)"
if ! wait $curl_portindex_pid; then
    echo "Fetching PortIndex failed: $?"
fi
## Ignore portindex errors on common ancestor
(cd ports/ && portindex)
git -C ports/ checkout -qf -
(cd ports/ && portindex -e)
endgroup
fi
fi


begingroup "Running postflight"
# Create macports user
sudo /opt/port/libexec/macports/postflight/postflight
endgroup
