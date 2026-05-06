package chserver

import (
	"net/http"
	"sort"

	rportplus "github.com/openrport/openrport/plus"
	"github.com/openrport/openrport/plus/capabilities/oauth"
	"github.com/openrport/openrport/plus/capabilities/status"
	"github.com/openrport/openrport/server/api"
	"github.com/openrport/openrport/server/api/users"
	"github.com/openrport/openrport/share/random"
)

// handleOAuthAuthorizationCode takes a request containing the OAuth authorization code parameters
// and sends it to the rport-plus plugin to be exchanged for valid access token and then username.
// The username can then be used to create a user (if required) and obtain a rport bearer token
func (al *APIListener) handleOAuthAuthorizationCode(w http.ResponseWriter, r *http.Request) {
	plusManager := al.Server.plusManager
	if plusManager == nil {
		al.jsonErrorResponse(w, http.StatusUnauthorized, rportplus.ErrPlusNotAvailable)
		return
	}

	capEx := plusManager.GetOAuthCapabilityEx()
	if capEx == nil {
		al.jsonErrorResponse(w, http.StatusForbidden, rportplus.ErrCapabilityNotAvailable(rportplus.PlusOAuthCapability))
		return
	}

	// if IDToken in use then possible that a permitted username
	// will be returned after the auth code exchange. if the user
	// isn't permitted then an error will be returned.
	token, username, err := capEx.PerformAuthCodeExchange(r)
	if err != nil {
		al.jsonErrorResponse(w, http.StatusUnauthorized, err)
		return
	}

	// if no previous err and an empty username then attempt to get
	// a permitted username from the oauth/identity provider
	if username == "" {
		username, err = capEx.GetPermittedUser(r, token)
		if err != nil {
			al.jsonErrorResponse(w, http.StatusUnauthorized, err)
			return
		}
	}

	if err := al.syncOAuthUserGroups(r, capEx, token, username); err != nil {
		al.jsonErrorResponse(w, http.StatusInternalServerError, err)
		return
	}

	// pass the username to the existing login logic to create the user (if required) and
	// get an rport-plus bearer token.
	al.handleLogin(username, "", "", true /* skipPasswordValidation */, w, r)
}

// handleGetDeviceAuth will return an RPort JWT token if the user has completed authorization
// and the user is permitted. If the user hasn't completed authorization yet then an
// error will be returned as per the OAuth device flow rules and the client can retry
// after the interval period returned in the device login info. If the response indicates
// a non-retryable error then the client should stop retrying and inform the end user.
func (al *APIListener) handleGetDeviceAuth(w http.ResponseWriter, r *http.Request) {
	plusManager := al.Server.plusManager
	if plusManager == nil {
		al.jsonErrorResponse(w, http.StatusUnauthorized, rportplus.ErrPlusNotAvailable)
		return
	}

	capEx := plusManager.GetOAuthCapabilityEx()
	if capEx == nil {
		al.jsonErrorResponse(w, http.StatusForbidden, rportplus.ErrCapabilityNotAvailable(rportplus.PlusOAuthCapability))
		return
	}

	token, username, errInfo, err := capEx.GetAccessTokenForDevice(r)
	if err != nil {
		if errInfo != nil {
			// error handling for the OAuth device flow is a little strange.
			// pending and slow_down errors aren't really errors. Also
			// the different providers seems to sometimes report errors via
			// the statusCode and sometimes not. Do the best that we can
			// here.
			response := api.NewSuccessPayload(errInfo)
			al.writeJSONResponse(w, errInfo.StatusCode, response)
		} else {
			// i think internal server error is ok as the providers really
			// should have returned the relevant errInfo.
			al.jsonErrorResponse(w, http.StatusInternalServerError, err)
		}
		return
	}

	// if no previous err and an empty username then attempt to get
	// a permitted username from the oauth/identity provider
	if username == "" {
		username, err = capEx.GetPermittedUserForDevice(r, token)
		if err != nil {
			al.jsonErrorResponse(w, http.StatusUnauthorized, err)
			return
		}
	}

	if err := al.syncOAuthUserGroups(r, capEx, token, username); err != nil {
		al.jsonErrorResponse(w, http.StatusInternalServerError, err)
		return
	}

	// pass the username to the existing login logic to create the user (if required) and
	// get an rport JWT bearer token.
	al.handleLogin(username, "", "", true /* skipPasswordValidation */, w, r)
}

// syncOAuthUserGroups inspects the OAuth capability for an optional
// GroupCapabilityEx implementation and, when present, ensures the local
// user record exists with the IdP-supplied groups before handleLogin runs.
// Without this hook a user created on first OAuth login receives only
// API.DefaultUserGroup; with it, group membership tracks the IdP on every
// login, making OIDC group claims authoritative for rportd authorisation.
//
// A no-op when:
//   - the capability does not implement GroupCapabilityEx
//   - the provider returns an empty group set (treated as "no opinion" --
//     existing local groups are preserved)
func (al *APIListener) syncOAuthUserGroups(r *http.Request, capEx oauth.CapabilityEx, accessToken, username string) error {
	groupCap, ok := capEx.(oauth.GroupCapabilityEx)
	if !ok || username == "" {
		return nil
	}
	groups, err := groupCap.GetUserGroups(r, accessToken)
	if err != nil {
		return err
	}
	if len(groups) == 0 {
		return nil
	}

	existing, err := al.userService.GetByUsername(username)
	if err != nil {
		return err
	}
	if existing == nil {
		pwd, err := random.UUID4()
		if err != nil {
			return err
		}
		return al.userService.Change(&users.User{
			Username: username,
			Password: pwd,
			Groups:   groups,
		}, "")
	}
	if sameGroups(existing.Groups, groups) {
		return nil
	}
	return al.userService.Change(&users.User{Groups: groups}, username)
}

func sameGroups(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	ac := append([]string(nil), a...)
	bc := append([]string(nil), b...)
	sort.Strings(ac)
	sort.Strings(bc)
	for i := range ac {
		if ac[i] != bc[i] {
			return false
		}
	}
	return true
}

// handlePlusStatus makes a request to the plugin for it's status/version info
func (al *APIListener) handlePlusStatus(w http.ResponseWriter, r *http.Request) {
	plusManager := al.Server.plusManager
	if plusManager == nil {
		statusInfo := status.PlusStatusInfo{
			IsEnabled: false,
			IsTrial:   true,
		}
		response := api.NewSuccessPayload(statusInfo)
		al.writeJSONResponse(w, http.StatusOK, response)
		return
	}

	statusCapEx := plusManager.GetStatusCapabilityEx()
	if statusCapEx == nil {
		al.jsonErrorResponse(w, http.StatusInternalServerError, rportplus.ErrCapabilityNotAvailable(rportplus.PlusStatusCapability))
		return
	}

	licCapEx := plusManager.GetLicenseCapabilityEx()
	if licCapEx == nil {
		al.jsonErrorResponse(w, http.StatusInternalServerError, rportplus.ErrCapabilityNotAvailable(rportplus.PlusStatusCapability))
		return
	}

	statusInfo := statusCapEx.GetStatusInfo()

	licInfo := licCapEx.GetLicenseInfo()
	if licInfo != nil {
		statusInfo.ValidLicense = true
		statusInfo.LicenseInfo = *licInfo
	}
	statusInfo.IsTrial = licCapEx.IsTrialMode()
	statusInfo.IsEnabled = true

	response := api.NewSuccessPayload(statusInfo)
	al.writeJSONResponse(w, http.StatusOK, response)
}
