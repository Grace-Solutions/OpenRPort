// Package main implements an open-source rport-plus plugin that provides an
// OIDC OAuth provider plus no-op stubs for the other plus capabilities so
// rportd can load it without a commercial license.
//
// Build: from src/Server, run
//   go build -buildmode=plugin -o rport-plus.so ./cmd/rport-plus-oidc
//
// Configure rportd:
//   [plus-plugin]
//     plugin_path = "/usr/local/lib/rport/rport-plus.so"
//   [plus-oauth]
//     provider          = "oidc"
//     authorize_url     = "https://issuer/protocol/openid-connect/auth"
//     token_url         = "https://issuer/protocol/openid-connect/token"
//     redirect_uri      = "https://rport.example/oauth/callback"
//     client_id         = "<client-id>"
//     client_secret     = "<client-secret>"
//     jwks_url          = "https://issuer/protocol/openid-connect/certs"
//     username_claim    = "preferred_username"
//     permitted_user_match = ".*"
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"go.etcd.io/bbolt"
	"golang.org/x/oauth2"

	alertingcap "github.com/openrport/openrport/plus/capabilities/alerting"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/clientupdates"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/measures"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/rules"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/rundata"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/templates"
	"github.com/openrport/openrport/plus/capabilities/alerting/entities/validations"
	"github.com/openrport/openrport/plus/capabilities/extendedpermission"
	licensecap "github.com/openrport/openrport/plus/capabilities/license"
	"github.com/openrport/openrport/plus/capabilities/oauth"
	"github.com/openrport/openrport/plus/capabilities/status"
	"github.com/openrport/openrport/plus/license"
	"github.com/openrport/openrport/server/notifications"
	"github.com/openrport/openrport/share/logger"
)

// pluginVersion is stamped into the status info; can be overridden via
// -ldflags "-X main.pluginVersion=..." at build time.
var pluginVersion = "openrport-oidc-plugin/0.1.0"

// StartPluginEx is the rportd entry point invoked once at plugin load time.
// We don't need any global setup; OIDC discovery is lazy.
func StartPluginEx(_ context.Context, _ *license.Config, l *logger.Logger) error {
	if l != nil {
		l.Infof("rport-plus-oidc plugin loaded (%s)", pluginVersion)
	}
	return nil
}

// ─── OAuth capability ────────────────────────────────────────────────────────

// InitOAuthCapabilityEx is the symbol rportd looks up to construct the OAuth
// provider. The returned value implements oauth.CapabilityEx.
func InitOAuthCapabilityEx(cap *oauth.Capability) oauth.CapabilityEx {
	return &oidcProvider{cfg: cap.Config, log: cap.Logger}
}

// oidcProvider implements oauth.CapabilityEx using OIDC discovery + the
// standard authorization-code flow.
type oidcProvider struct {
	cfg *oauth.Config
	log *logger.Logger

	mu       sync.Mutex
	verifier *oidc.IDTokenVerifier
	oauth2   *oauth2.Config
	provider *oidc.Provider
}

func (p *oidcProvider) ValidateConfig() error {
	if p.cfg == nil {
		return oauth.ErrMissingConfig
	}
	if p.cfg.Provider == "" {
		return oauth.ErrMissingProvider
	}
	if p.cfg.BaseAuthorizeURL == "" {
		return oauth.ErrMissingAuthorizeURL
	}
	if p.cfg.TokenURL == "" {
		return oauth.ErrMissingTokenURL
	}
	if p.cfg.RedirectURI == "" {
		return oauth.ErrMissingRedirectURI
	}
	if p.cfg.ClientID == "" {
		return oauth.ErrMissingClientID
	}
	if p.cfg.ClientSecret == "" {
		return oauth.ErrMissingClientSecret
	}
	if p.cfg.PermittedUserMatch != "" && p.cfg.CompiledPermittedUserMatch == nil {
		re, err := regexp.Compile(p.cfg.PermittedUserMatch)
		if err != nil {
			return oauth.ErrInvalidPermittedUserMatch
		}
		p.cfg.CompiledPermittedUserMatch = re
	}
	return nil
}

// initOAuth lazily builds the oauth2 + verifier objects. Performed on the
// first request so a temporary issuer outage at boot doesn't kill rportd.
func (p *oidcProvider) initOAuth(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.oauth2 != nil {
		return nil
	}
	scopes := []string{oidc.ScopeOpenID, "profile", "email"}
	if p.cfg.RequiredGroupID != "" || p.cfg.RoleClaim != "" {
		scopes = append(scopes, "groups")
	}
	p.oauth2 = &oauth2.Config{
		ClientID:     p.cfg.ClientID,
		ClientSecret: p.cfg.ClientSecret,
		RedirectURL:  p.cfg.RedirectURI,
		Endpoint: oauth2.Endpoint{
			AuthURL:  p.cfg.BaseAuthorizeURL,
			TokenURL: p.cfg.TokenURL,
		},
		Scopes: scopes,
	}
	if p.cfg.JWKSURL != "" {
		ks := oidc.NewRemoteKeySet(ctx, p.cfg.JWKSURL)
		p.verifier = oidc.NewVerifier(deriveIssuer(p.cfg.JWKSURL), ks, &oidc.Config{
			ClientID:        p.cfg.ClientID,
			SkipIssuerCheck: true,
		})
	}
	return nil
}

func (p *oidcProvider) GetLoginInfo() (*oauth.LoginInfo, error) {
	if err := p.initOAuth(context.Background()); err != nil {
		return nil, err
	}
	state, err := randomState()
	if err != nil {
		return nil, err
	}
	authURL := p.oauth2.AuthCodeURL(state, oauth2.AccessTypeOnline)
	return &oauth.LoginInfo{
		LoginMsg:     "Sign in with " + p.cfg.Provider,
		AuthorizeURL: authURL,
		LoginURI:     oauth.DefaultLoginURI,
		State:        state,
		Expiry:       time.Now().Add(10 * time.Minute),
	}, nil
}

func (p *oidcProvider) PerformAuthCodeExchange(r *http.Request) (string, string, error) {
	if err := p.initOAuth(r.Context()); err != nil {
		return "", "", err
	}
	code := r.URL.Query().Get("code")
	if code == "" {
		_ = r.ParseForm()
		code = r.FormValue("code")
	}
	if code == "" {
		return "", "", errors.New("missing authorization code")
	}
	tok, err := p.oauth2.Exchange(r.Context(), code)
	if err != nil {
		return "", "", fmt.Errorf("token exchange failed: %w", err)
	}
	username := ""
	if rawID, ok := tok.Extra("id_token").(string); ok && rawID != "" && p.verifier != nil {
		idTok, verr := p.verifier.Verify(r.Context(), rawID)
		if verr == nil {
			username = p.extractUsername(idTok)
		}
	}
	return tok.AccessToken, username, nil
}

func (p *oidcProvider) GetPermittedUser(r *http.Request, accessToken string) (string, error) {
	if err := p.initOAuth(r.Context()); err != nil {
		return "", err
	}
	if p.provider == nil {
		return "", errors.New("oidc provider not initialized; set jwks_url to enable userinfo")
	}
	src := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: accessToken})
	ui, err := p.provider.UserInfo(r.Context(), src)
	if err != nil {
		return "", fmt.Errorf("userinfo failed: %w", err)
	}
	claims := map[string]interface{}{}
	if err := ui.Claims(&claims); err != nil {
		return "", fmt.Errorf("decode userinfo: %w", err)
	}
	username, _ := claims[p.usernameClaimName()].(string)
	if username == "" {
		username = ui.Subject
	}
	if !p.userPermitted(username) {
		return "", fmt.Errorf("user %q not permitted", username)
	}
	return username, nil
}

// ─── Device-flow stubs (not implemented; CLI flow not supported here) ────────

func (p *oidcProvider) GetLoginInfoForDevice(_ *http.Request) (*oauth.DeviceLoginInfo, error) {
	return nil, errors.New("device flow " + oauth.ErrProviderNotSupportedMsg)
}

func (p *oidcProvider) GetAccessTokenForDevice(_ *http.Request) (string, string, *oauth.DeviceAuthStatusErrorInfo, error) {
	return "", "", nil, errors.New("device flow " + oauth.ErrProviderNotSupportedMsg)
}

func (p *oidcProvider) GetPermittedUserForDevice(_ *http.Request, _ string) (string, error) {
	return "", errors.New("device flow " + oauth.ErrProviderNotSupportedMsg)
}

// ─── helpers ─────────────────────────────────────────────────────────────────

func (p *oidcProvider) usernameClaimName() string {
	if p.cfg.UsernameClaim != "" {
		return p.cfg.UsernameClaim
	}
	return "preferred_username"
}

func (p *oidcProvider) extractUsername(t *oidc.IDToken) string {
	claims := map[string]interface{}{}
	if err := t.Claims(&claims); err != nil {
		return ""
	}
	if v, ok := claims[p.usernameClaimName()].(string); ok && v != "" {
		return v
	}
	if v, ok := claims["email"].(string); ok && v != "" {
		return v
	}
	return t.Subject
}

func (p *oidcProvider) userPermitted(username string) bool {
	if username == "" {
		return false
	}
	if p.cfg.CompiledPermittedUserMatch != nil {
		return p.cfg.CompiledPermittedUserMatch.MatchString(username)
	}
	return true
}

func randomState() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func deriveIssuer(jwksURL string) string {
	// strip the trailing /.well-known/jwks.json or /protocol/openid-connect/certs
	for _, suffix := range []string{"/.well-known/jwks.json", "/protocol/openid-connect/certs", "/jwks", "/keys"} {
		if strings.HasSuffix(jwksURL, suffix) {
			return strings.TrimSuffix(jwksURL, suffix)
		}
	}
	return jwksURL
}

// ─── Status capability stub ──────────────────────────────────────────────────

func InitPlusStatusCapabilityEx(_ *status.Capability) status.CapabilityEx {
	return &statusStub{}
}

type statusStub struct{}

func (s *statusStub) GetStatusInfo() *status.PlusStatusInfo {
	return &status.PlusStatusInfo{
		IsEnabled:     true,
		IsTrial:       false,
		ValidLicense:  true,
		PlusVersion:   pluginVersion,
		PlusBuildTime: time.Now().UTC().Format(time.RFC3339),
	}
}

// ─── License capability stub (open-source: unlimited, always valid) ──────────

func InitPlusLicenseCapabilityEx(_ *licensecap.Capability) licensecap.CapabilityEx {
	return &licenseStub{}
}

type licenseStub struct {
	notify licensecap.LicenseInfoAvailableNotifier
}

func (l *licenseStub) SetLicenseInfoAvailableNotifier(fn licensecap.LicenseInfoAvailableNotifier) {
	l.notify = fn
	if fn != nil {
		go fn()
	}
}
func (l *licenseStub) LicenseInfoAvailable() bool { return true }
func (l *licenseStub) IsTrialMode() bool          { return false }
func (l *licenseStub) GetLicenseInfo() *licensecap.PlusLicenseInfo {
	return &licensecap.PlusLicenseInfo{MaxClients: alertingcap.NoLimit, MaxUsers: alertingcap.NoLimit}
}
func (l *licenseStub) GetMaxClients() int { return alertingcap.NoLimit }
func (l *licenseStub) GetMaxUsers() int   { return alertingcap.NoLimit }

// ─── Extended-permission capability stub (allow everything) ──────────────────

func InitPlusExtendedPermissionCapabilityEx(_ *extendedpermission.Capability) extendedpermission.CapabilityEx {
	return &extPermStub{}
}

type extPermStub struct{}

func (e *extPermStub) ValidateExtendedTunnelPermission(_ *http.Request, _ []extendedpermission.PermissionParams) error {
	return nil
}
func (e *extPermStub) ValidateExtendedCommandPermission(_ *http.Request, _ []extendedpermission.PermissionParams) error {
	return nil
}
func (e *extPermStub) ValidateExtendedCommandPermissionRaw(_ string, _ bool, _ []extendedpermission.PermissionParams) error {
	return nil
}
func (e *extPermStub) ValidateExtendedDeleteNonOwnedTunnelPermissionRaw(_ []extendedpermission.PermissionParams) error {
	return nil
}

// ─── Alerting capability stub (no-op service) ────────────────────────────────

func InitAlertingServiceCapabilityEx(_ *alertingcap.Capability) alertingcap.CapabilityEx {
	return &alertingStub{svc: &alertingServiceStub{}}
}

type alertingStub struct {
	svc *alertingServiceStub
}

func (a *alertingStub) Init(_ *bbolt.DB) error                 { return nil }
func (a *alertingStub) GetService() alertingcap.Service        { return a.svc }
func (a *alertingStub) RunRulesTest(_ context.Context, _ *rundata.RunData, _ *logger.Logger) (*rundata.TestResults, validations.ErrorList, error) {
	return nil, nil, nil
}

type alertingServiceStub struct{}

func (s *alertingServiceStub) Run(_ context.Context, _ string, _ notifications.Dispatcher, _ int) {}
func (s *alertingServiceStub) Stop() error                                                         { return nil }
func (s *alertingServiceStub) LoadDefaultRuleSet() error                                           { return nil }
func (s *alertingServiceStub) PutClientUpdate(_ *clientupdates.Client) error                      { return nil }
func (s *alertingServiceStub) PutMeasurement(_ *measures.Measure) error                           { return nil }
func (s *alertingServiceStub) GetAllTemplates() (templates.TemplateList, error)                   { return nil, nil }
func (s *alertingServiceStub) GetTemplate(_ templates.TemplateID) (*templates.Template, error)    { return nil, alertingcap.ErrEntityNotFound }
func (s *alertingServiceStub) SaveTemplate(_ *templates.Template) (validations.ErrorList, error) { return nil, nil }
func (s *alertingServiceStub) DeleteTemplate(_ templates.TemplateID) error                       { return nil }
func (s *alertingServiceStub) LoadRuleSet(_ rules.RuleSetID) (*rules.RuleSet, error)             { return nil, alertingcap.ErrEntityNotFound }
func (s *alertingServiceStub) SaveRuleSet(_ *rules.RuleSet) (validations.ErrorList, error)        { return nil, nil }
func (s *alertingServiceStub) DeleteRuleSet(_ rules.RuleSetID) error                              { return nil }
func (s *alertingServiceStub) SetRuleSet(_ *rules.RuleSet)                                        {}
func (s *alertingServiceStub) GetProblem(_ rules.ProblemID) (*rules.Problem, error)              { return nil, nil }
func (s *alertingServiceStub) GetLatestProblem(_ rules.RuleID, _ string) (*rules.Problem, error) { return nil, nil }
func (s *alertingServiceStub) SetProblemActive(_ rules.ProblemID) error                          { return nil }
func (s *alertingServiceStub) SetProblemResolved(_ rules.ProblemID, _ time.Time) error           { return nil }
func (s *alertingServiceStub) GetLatestProblems(_ int) ([]*rules.Problem, error)                 { return nil, nil }
func (s *alertingServiceStub) GetSampleData(_ string) (*rundata.SampleData, error)               { return &rundata.SampleData{}, nil }
