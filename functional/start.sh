#!/bin/bash -ex
#
# Start the test vault container
#
set -e
DOCKER_NAME=testvault
PORT=8201
export VAULT_ADDR="http://127.0.0.1:${PORT}"

TMP_CONFIG_DIR=$(mktemp -q -d /tmp/$0.XXXXXX)
TMP_CONFIG_VAULT="${TMP_CONFIG_DIR}/vault.json"
trap "rm -rf $TMP_CONFIG_DIR" EXIT

cat <<EOF > $TMP_CONFIG_VAULT
{
	"backend": {
		"file": {
			"path": "/vault/file"
		}
	},
	"listener": {
		"tcp": {
			"address": "0.0.0.0:${PORT}",
			"tls_disable": 1
		}
	},
	"default_lease_ttl": "168h",
	"max_lease_ttl": "720h",
	"disable_mlock": true
}
EOF
chmod a+r $TMP_CONFIG_VAULT

docker stop $DOCKER_NAME 2>/dev/null || true
docker rm $DOCKER_NAME 2>/dev/null || true
docker run --name $DOCKER_NAME -h $DOCKER_NAME -d \
    --cap-add IPC_LOCK \
	-v $TMP_CONFIG_VAULT:/etc/vault/config.json:ro \
	--network host \
	vault server -config /etc/vault/config.json

#
# Wait for vault to come up
#
CNT=0
while ! curl -sI "$VAULT_ADDR/v1/sys/health" > /dev/null; do
	sleep 1
	CNT=$(expr $CNT + 1)
	if [ $CNT -gt 20 ]
	then
		docker logs $DOCKER_NAME
		exit 1
	fi
done

#
# Initialize the vault
#
ansible-playbook -v test_init.yml
source ./vaultenv.sh
ansible-playbook -v test_enable_kv.yml
exit $?
