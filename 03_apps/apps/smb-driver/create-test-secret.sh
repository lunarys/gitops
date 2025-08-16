if [ -z "$1" ]; then
	echo "Enter smb volume password:"
	read PASSWORD
fi

TESTNS=smb-test
USER=testuser
PASSWORD="${1:-$PASSWORD}"
DOMAIN="WORKGROUP"

kubectl -n $TESTNS create secret generic smb-creds \
	--from-literal username=$USER \
	--from-literal domain=$DOMAIN \
	--from-literal password=$PASSWORD
