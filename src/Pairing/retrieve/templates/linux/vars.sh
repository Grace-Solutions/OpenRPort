#
# Global Variables for installation and update
#
CONF_DIR=/etc/rport
CONFIG_FILE=${CONF_DIR}/rport.conf
USER=rport
ARCH=$(uname -m | sed s/"armv\(6\|7\)l"/'armv\1'/ | sed s/aarch64/arm64/)

# Server-injected download endpoints. Default release channel can still be
# overridden via the -t flag in the script body.
BINARIES_BASE_URL="{{ .BinariesBaseUrl }}"
TACO_BASE_URL="{{ .TacoBaseUrl }}"
REPO_BASE_URL="{{ .RepoBaseUrl }}"
RELEASE="{{ .Release }}"