package retrieve

import (
	"fmt"
	"github.com/gorilla/mux"
	"github.com/openrport/rport-pairing/deposit"
	"github.com/patrickmn/go-cache"
	"net/http"
)

type InstallerHandler struct {
	StaticDeposit deposit.Deposit
	Cache         *cache.Cache
	Downloads     Downloads
}

// Handle the request for previously pairing data aka client credentials identified by the pairing code.
// If pairing code exists, render an installer script with client credentials as variables dynamically inserted.
func (rh *InstallerHandler) ServeHTTP(rw http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	pairingCode := vars["pairingCode"]
	os := clientOs(r)
	var dep deposit.Deposit
	if pairingCode == rh.StaticDeposit.Code {
		dep = rh.StaticDeposit
	} else {
		val, found := rh.Cache.Get(pairingCode)
		if !found {
			rw.WriteHeader(http.StatusNotFound)
			fmt.Fprintf(rw, "#No pairing found by pairing code %s\n", pairingCode)
			return
		}
		dep = val.(deposit.Deposit)
	}
	renderInstaller(rw, os, dep, rh.Downloads.withDefaults())
}

func renderInstaller(rw http.ResponseWriter, os string, dep deposit.Deposit, dl Downloads) {
	switch os {
	case "windows":
		rw.Header().Add("Content-Disposition", "attachment; filename=\"rport-installer.ps1\"")
		includeFileRaw(rw, "templates/windows/installer_init.ps1")
		includeFile(rw, "templates/header.txt")
		renderTemplate(rw, "templates/windows/vars.ps1", InstallerData{Deposit: deposit.SanitizeForPowerShell(dep), Downloads: dl})
		includeFile(rw, "templates/windows/functions.ps1")
		includeFile(rw, "templates/windows/install.ps1")
	default:
		rw.Header().Add("Content-Disposition", "attachment; filename=\"rport-installer.sh\"")
		includeFileRaw(rw, "templates/linux/init.sh")
		includeFile(rw, "templates/header.txt")
		renderTemplate(rw, "templates/linux/installer_vars.sh", InstallerData{Deposit: deposit.SanitizeForBash(dep), Downloads: dl})
		renderTemplate(rw, "templates/linux/vars.sh", InstallerData{Deposit: deposit.SanitizeForBash(dep), Downloads: dl})
		includeFile(rw, "templates/linux/functions.sh")
		includeFile(rw, "templates/linux/install.sh")
	}
}
