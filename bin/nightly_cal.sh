#!/bin/bash

[ -f /home/coatli/MANUAL_MODE ] && { echo "file /home/coatli/MANUAL_MODE present, aborting" ; exit 1 ; }

source /usr/local/var/coatli/bin/redux_funcs_coatli.sh
test=

# just in case
rm $REDUX_LOCKFILE /home/coatli/monitoring.txt 2>/dev/null

date -u

coatli_full_redux
