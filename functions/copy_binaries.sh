#!/bin/bash

# Copy over the latest binaries into /usr/bin so they are in path
function copy_binaries {

	handle_om
	handle_pivnet_cli
	handle_govc
}

function handle_om {
    set +e
		om_cli=$(find / -name om-linux 2>/dev/null)
		if [ "$om_cli" != "" ]; then
			chmod +x $om_cli
			cp $om_cli /usr/bin/om
		fi
    set -e
}

function handle_pivnet_cli {
    set +e
		pivnet_cli=$(find / -name "pivnet-linux-amd64*" 2>/dev/null)
		if [ "$pivnet_cli" != "" ]; then
			chmod +x $pivnet_cli
			cp $pivnet_cli /usr/bin/pivnet-cli
		fi
    set -e
}

function handle_govc {
    set +e
		govc_gz=$(find / -name govc_linux_amd64.gz 2>/dev/null)
		if [ "$govc_gz" != "" ]; then
			gunzip $govc_gz
		fi
		
		govc=$(find / -name govc_linux_amd64 2>/dev/null)
		if [ "$govc" != "" ]; then			
			chmod +x $govc
			cp $govc /usr/bin/govc
		fi
    set -e
}

copy_binaries