#
# Dynamically inserted variables
#
FINGERPRINT="{{ .Fingerprint}}"
CONNECT_URL="{{ .ConnectUrl}}"
CLIENT_ID="{{ .ClientId}}"
PASSWORD="{{ .Password}}"

# Server-supplied tags. Rendered as a POSIX-shell array; empty when the
# pairing deposit had no tags. Merged with any -g <tag> CLI argument when
# client_attributes.json is written.
SERVER_TAGS=({{ .TagsBash }})

#
# Global static installer vars
#
TMP_FOLDER=/tmp/rport-install
FORCE=1
USE_ALTERNATIVE_MACHINEID=0
LOG_DIR=/var/log/rport
LOG_FILE=${LOG_DIR}/rport.log