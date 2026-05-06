#
# Dynamically inserted variables
#
$fingerprint = "{{ .Fingerprint}}"
$connect_url = "{{ .ConnectUrl}}"
$client_id = "{{ .ClientId}}"
$password = "{{ .Password}}"

# Server-supplied tags. PowerShell array, empty when the pairing deposit
# carried no tags. Merged with any -g <tag> CLI argument when
# client_attributes.json is written.
$server_tags = @({{ .TagsPowerShell }})

# Server-injected download endpoints used by install/update flows. The -t
# CLI flag can still override $release at runtime.
$binaries_base_url = "{{ .BinariesBaseUrl }}"
$taco_base_url     = "{{ .TacoBaseUrl }}"
$repo_base_url     = "{{ .RepoBaseUrl }}"
$release           = "{{ .Release }}"

# Public pairing-service URL the rendered scripts point users at when they
# need the update entry-point.
$pairing_url = "{{ .PairingUrl }}"
$update_url  = "$( $pairing_url )/update"