#!/bin/bash

##--------------------------------------------------------------------
## Copyright (c) 2018 OSIsoft, LLC
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##--------------------------------------------------------------------

##################
# Snap installer
#
# Author: Massimiliano Pinto

set -e
#set -x

logger -p local0.info -t "SnapUpdater[${$}]" "launching $0 $1 $2 $3 $4 $5 $6"

trap '' HUP
trap '' INT
trap '' TERM
trap '' QUIT

SNAP_INSTALLER_VER="1.0"
INSTALLER_CREDITS="Snap installer/updater v${SNAP_INSTALLER_VER} Copyright (c) 2018 OSIsoft, LLC"

#########################################################
#
# The remote repository directory layout should be:
# /xyz/snaps/$OS_ARCH
# snap name ino file must be present
# /xyz/snaps/$OS_ARCH/xyz.info
#
# xyz.info file contains only the version, say "1.3.15"
#
#########################################################

# Get system arch
OS_ARCH=`arch`
# Remote repository can use armhf instead of armv7l
if [ "${OS_ARCH}" = "armv7l" ]; then
	OS_ARCH="armhf"
fi

# Snaps path
SNAPS_PATH="snaps"
# Snap version path prefix per arch
SNAP_VERSION_URL_PREFIX="/$SNAPS_PATH/$OS_ARCH/"
# Snap package path prefix per arch
SNAP_PACKAGE_URL_PREFIX="/$SNAPS_PATH/$OS_ARCH/"

# This var will hold the found version in the remote repository
NEW_PACKAGE_VERSION=""

# Working dir for downloaded files
WORKDIR=`mktemp -d`
trap "rm -rf $WORKDIR" EXIT KILL

# Handle optional switches
DEVMODE=""
echo "$@" | grep -q -- --devmode && DEVMODE="--devmode"
FORCE_INSTALL=""
echo "$@" | grep -q -- --force && FORCE_INSTALL="Y"
MANAGE_SERVICE=""
echo "$@" | grep -q -- --manage && MANAGE_SERVICE="Y"

# Error reporting routine, it aborts the execution when called
error()
{
        echo -e "$1"

	# Abort script execution
        exit 1
}

# Get Snap version from remote repository
is_available()
{
	# No error reporting when using -q
	wget -O- -q "${SNAP_REPO_HOST}${SNAP_VERSION_URL_PREFIX}$1.info"
}

# Check whether the snap package can be upgraded
is_upgradeable()
{
	# Get snap info
	FIND_SNAP=`snap list | grep $1 | awk '{$1=$1}1' OFS=" " || echo ""`

	# Abort if not installed
	if [ ! "${FIND_SNAP}" ] && [ ! "${FORCE_INSTALL}" ]; then
		error "\nError: snap [$1] is not installed, can't upgrade. Use --force option."
	fi

	# Get current snap version
	INSTVER="$(echo ${FIND_SNAP} | awk '{print $2}')"
	# Get remote available version
	REMVER="$(is_available $1)" || error "\nThe snap [$1] is not available in remote repo."
	# Set new version in NEW_PACKAGE_VERSION var
	NEW_PACKAGE_VERSION=${REMVER}

	# Return success for upgrade or abort with up-to-date
	# Note: sort -V, --version compare version strings
	if [ "$(printf '%s\n' "$INSTVER" "$REMVER" | sort -V | head -n 1)" != "$REMVER" ]; then
		return 0
	else
		logger -p local0.info -t "SnapUpdater[${$}]" "The snap [$1] is up to date (curr ver ${INSTVER}, remote ${NEW_PACKAGE_VERSION})"
		error "\nThe snap [$1] is up to date (curr ver ${INSTVER}, remote ${NEW_PACKAGE_VERSION})"
	fi
}

# Check whether the snap package is already installed 
is_snap_installed()
{
	# Get snap info
	FIND_SNAP=`snap list | grep $1 | awk '{$1=$1}1' OFS=", "`

	# Abort if not installed and no force option
	if [ "${FIND_SNAP}" ] && [ ! "${FORCE_INSTALL}" ]; then
		error "Snap [$1] is already installed: ${FIND_SNAP}. Use --force option to reinstall."
	fi

	logger -p local0.info -t "SnapUpdater[${$}]" "Snap $1 is installed"
}

# Perform the Snap installation
install_snap()
{
	PACKAGE_ARCH=$OS_ARCH
	# Remote repository can use amd64 instead of x86_64
	if [ "${PACKAGE_ARCH}" = "x86_64" ]; then
		PACKAGE_ARCH="amd64"
	fi
	URL="${SNAP_REPO_HOST}${SNAP_PACKAGE_URL_PREFIX}$1_$(is_available $1)_$PACKAGE_ARCH.snap" ||
		error "Error: the snap [$1], arch $OS_ARCH is not available for download."

	if [ ! "${NEW_PACKAGE_VERSION}" ]; then
		NEW_PACKAGE_VERSION=`echo ${URL} | awk -F'_' '{print $3}'`
	fi

	logger -p local0.info -t "SnapUpdater[${$}]" "New Snap [$1] version [${NEW_PACKAGE_VERSION}] is ready to be installed"

	NAME="$(basename $URL)"
	cd $WORKDIR

	# Wget with -q doesn't report errors, we only handle the return code
	wget_code=0
	wget --show-progress -q -O ${NAME} ${URL} || wget_code=1

	if [ "${wget_code}" -ne 0 ]; then
		echo "Error: failed to download snap [${NAME}] from repo"
		return 1
	fi

	logger -p local0.info -t "SnapUpdater[${$}]" "New snap [$1] dowloaded, version ${NEW_PACKAGE_VERSION}"

	# The snap install MUST be called by root: the user calling the utility must be in sudoers
	sudo snap install ${DEVMODE} ./${NAME}

	# Leave temp dir
	cd - >/dev/null 2>&1

	logger -p local0.info -t "SnapUpdater[${$}]" "New snap [$1] version ${NEW_PACKAGE_VERSION} has been installed."
}

# Print usage and credits
usage()
{
	echo "Snap installer/updater v${SNAP_INSTALLER_VER} Copyright (c) 2018 OSIsoft, LLC"
	echo
	echo "usage: snap-get <command> <snapname> [--devmode] [--force] [--manage]"
	echo
	echo "commands:"
	echo "  install - install a snap from a remote repository"
	echo "  upgrade - upgrade a snap from a remote repository"
	echo
	echo " force the snap install/upgrade with --force"
	echo " manage snap application stop/start with --manage"
	echo "    this assumes such command exists: snap_name stop|start"
	echo
	echo "for snaps needing --devmode installs, use the optional --devmode switch"
	exit 0
}

###
# Main body
#

# The snap package name is mandatory
[ -n "$2" ] || usage

OPERATION_TYPE=$1
PACKAGE_NAME=$2

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        --repo)
            SNAP_REPO_HOST=$VALUE
            ;;
        *)
            #echo "Unknown flag $PARAM"
        ;;
    esac
    shift
done

if [ ! "${SNAP_REPO_HOST}" ]; then
	SNAP_REPO_HOST="http://127.0.0.1:8432"
fi

# Check snap operation type
case ${OPERATION_TYPE} in
	# Snap install	
	install)
		echo "Installing snap [${PACKAGE_NAME}] from repo [${SNAP_REPO_HOST}${SNAP_PACKAGE_URL_PREFIX}]"
		logger -p local0.info -t "SnapUpdater[${$}" "Installing snap [${PACKAGE_NAME}] from repo [${SNAP_REPO_HOST}${SNAP_PACKAGE_URL_PREFIX}]"

		# Check if already installed then proceed with installation
		is_snap_installed ${PACKAGE_NAME} && install_snap ${PACKAGE_NAME}
		;;

	# Snap upgrade
	upgrade)
		echo "Checking new snap [${PACKAGE_NAME}] version from repo [${SNAP_REPO_HOST}${SNAP_PACKAGE_URL_PREFIX}] ..."
		logger -p local0.info -t "SnapUpdater[${$}]" "Checking new snap [${PACKAGE_NAME}] version from repo [${SNAP_REPO_HOST}${SNAP_PACKAGE_URL_PREFIX}] ..."
		# get service command for selected snap, if available
		SERVICE_COMMAND=`command -v ${PACKAGE_NAME} || echo ""`

		# Check whether the installed package can be upgraded
		if is_upgradeable ${PACKAGE_NAME}; then
			echo "Upgrading snap [${PACKAGE_NAME}] to version [${NEW_PACKAGE_VERSION}]"
			logger -p local0.info -t "SnapUpdater[${$}" "Upgrading snap [${PACKAGE_NAME}] to version [${NEW_PACKAGE_VERSION}]"

			if [ "${MANAGE_SERVICE}" ] && [ ! "${FORCE_INSTALL}" ]; then
				echo "Calling [${PACKAGE_NAME} stop]"
				logger -p local0.info -t "SnapUpdater[${$}" "Calling [${SERVICE_COMMAND} stop]"
				sleep 10
				# call snap name stop
				${SERVICE_COMMAND} stop
			fi

			logger -p local0.info -t "SnapUpdater[${$}" "Try installing the new snap ${PACKAGE_NAME} version ${NEW_PACKAGE_VERSION}"

			# Install the snap
			install_snap ${PACKAGE_NAME}
			install_code=$?

			logger -p local0.info -t "SnapUpdater[${$}" "Snap ${PACKAGE_NAME} installed: ret code ${install_code}"
        
			if [ "${install_code}" -ne 0 ]; then
				if  [ "${MANAGE_SERVICE}" ] && [ ! "${FORCE_INSTALL}" ]; then
					echo "... waiting for restart ..."
					sleep 5
				fi
			fi

			if [ "${MANAGE_SERVICE}" ] && [ ! "${FORCE_INSTALL}" ]; then
				echo "Calling [${PACKAGE_NAME} start]"
				logger -p local0.info -t "SnapUpdater[${$}" "Calling [${PACKAGE_NAME} start]"
				# call snap name start
				${SERVICE_COMMAND} start || echo ""
				logger -p local0.info -t "SnapUpdater[${$}" "[${PACKAGE_NAME}] started"
			fi
		fi

		logger -p local0.info -t "SnapUpdater[${$}" "Snap ${PACKAGE_NAME} upgrade done. New version ${NEW_PACKAGE_VERSION}"
		exit ${install_code}

		;;
	# Any other option goes to 'usage'
	*)
		usage
		;;
esac
