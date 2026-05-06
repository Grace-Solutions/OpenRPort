package rportplus

func IsPlusEnabled(config PlusConfig) bool {
	return config.PluginConfig != nil &&
		config.PluginConfig.PluginPath != ""
}

func HasLicenseConfig(config PlusConfig) bool {
	return IsPlusEnabled(config) && config.LicenseConfig != nil
}

func IsPlusOAuthEnabled(config PlusConfig) bool {
	return IsPlusEnabled(config) && config.OAuthConfig != nil
}

func IsOAuthPermittedUserList(config PlusConfig) bool {
	if !IsPlusEnabled(config) {
		return false
	}
	return config.OAuthConfig != nil && config.OAuthConfig.PermittedUserList
}

// IsLocalLoginAllowed reports whether the built-in username/password login
// endpoints should remain reachable while OAuth is configured. Used to keep a
// local break-glass admin path available when an external IdP is unreachable.
func IsLocalLoginAllowed(config PlusConfig) bool {
	if !IsPlusOAuthEnabled(config) {
		return true
	}
	return config.OAuthConfig.AllowLocalLogin
}
