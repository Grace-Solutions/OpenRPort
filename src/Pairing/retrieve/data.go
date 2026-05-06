package retrieve

import (
	"fmt"
	"strings"

	"github.com/openrport/rport-pairing/deposit"
)

// Downloads holds the URLs and release channel the installer/update scripts
// use to fetch the rport client, tacoscript and DEB/RPM packages. It is
// populated once at process start from the pairing config and merged with
// the per-pairing Deposit when rendering a script. Empty fields are
// substituted with upstream defaults at render time so an unconfigured
// pairing service stays backwards compatible.
type Downloads struct {
	BinariesBaseUrl string `mapstructure:"binaries_base_url"`
	TacoBaseUrl     string `mapstructure:"taco_base_url"`
	RepoBaseUrl     string `mapstructure:"repo_base_url"`
	Release         string `mapstructure:"release"`
}

const (
	defaultBinariesBaseUrl = "https://downloads.openrport.io"
	defaultTacoBaseUrl     = "https://downloads.openrport.io"
	defaultRepoBaseUrl     = "https://repo.openrport.io"
	defaultRelease         = "stable"
)

// withDefaults returns a copy of d with empty fields replaced by upstream
// defaults so templates never render bare strings.
func (d Downloads) withDefaults() Downloads {
	if d.BinariesBaseUrl == "" {
		d.BinariesBaseUrl = defaultBinariesBaseUrl
	}
	if d.TacoBaseUrl == "" {
		d.TacoBaseUrl = defaultTacoBaseUrl
	}
	if d.RepoBaseUrl == "" {
		d.RepoBaseUrl = defaultRepoBaseUrl
	}
	if d.Release == "" {
		d.Release = defaultRelease
	}
	return d
}

// InstallerData is the value passed to the Go templates. It composes a
// (sanitized) Deposit with the service-level Downloads config plus a few
// pre-rendered shell snippets so the templates stay free of looping logic.
type InstallerData struct {
	deposit.Deposit
	Downloads
}

// TagsBash renders the Tags slice as the body of a POSIX shell array, e.g.
// `"prod" "us-east"`. Each entry is wrapped in double quotes; sanitization
// of the entries is the caller's responsibility (see deposit.SanitizeForBash).
func (d InstallerData) TagsBash() string {
	if len(d.Tags) == 0 {
		return ""
	}
	parts := make([]string, len(d.Tags))
	for i, t := range d.Tags {
		parts[i] = fmt.Sprintf(`"%s"`, t)
	}
	return strings.Join(parts, " ")
}

// TagsPowerShell renders the Tags slice as the body of a PowerShell array,
// e.g. `"prod","us-east"`. Sanitization is the caller's responsibility (see
// deposit.SanitizeForPowerShell).
func (d InstallerData) TagsPowerShell() string {
	if len(d.Tags) == 0 {
		return ""
	}
	parts := make([]string, len(d.Tags))
	for i, t := range d.Tags {
		parts[i] = fmt.Sprintf(`"%s"`, t)
	}
	return strings.Join(parts, ",")
}
