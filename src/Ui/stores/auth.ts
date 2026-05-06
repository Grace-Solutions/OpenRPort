import { defineStore } from 'pinia';
import type { AuthProviderInfo, ILoginInput, OAuthLoginInfo, TwoFa } from '~/types';

export const useTokenStore = defineStore('token', {
	state: () => ({
		authenticated: false,
		showTwoFa: false,
		loading: false,
		errors: [] as Array<string>,
		two_fa: {} as TwoFa,
		twoFaToken: null as string,
		provider: null as AuthProviderInfo | null,
		oauthLoginInfo: null as OAuthLoginInfo | null,
	}),
	actions: {
		async getLoginToken(credentials: ILoginInput) {
			const { $api } = useNuxtApp();
			this.loading = true;
			const token = useCookie<string>('token');
			const is_authenticated = useCookie<boolean>('is_authenticated');
			try {
				const response = await $api.auth.login(credentials);
				if (response?.data.token) {
					if (response?.data?.two_fa !== null) {
						this.twoFaToken = response.data.token;
						this.two_fa = response.data.two_fa;
						this.showTwoFa = true;
					}
					else {
						token.value = response.data.token;
						is_authenticated.value = true;
						this.authenticated = true;
					}
				}
				this.loading = false;
			}
			catch (error: any) {
				if (error.response && error.response.data && error.response.data.errors) {
					const apiErrors = error.response.data.errors;
					if (apiErrors.length > 0) {
						const errorMessage = apiErrors[0].detail || apiErrors[0].title;
						this.errors = errorMessage;
					}
				}
				else {
					this.$state.errors = ['An error occurred. Please try again later.'];
				}
				this.loading = false;
			}
		},
		async verifyTwoFa(credentials: ILoginInput, code: string) {
			const { $api } = useNuxtApp();
			this.loading = true;
			const token = useCookie<string>('token');
			const is_authenticated = useCookie<boolean>('is_authenticated');
			try {
				const response = await $api.auth.verify2fa(credentials, this.twoFaToken, code);
				if (response?.data.token) {
					token.value = response.data.token;
					is_authenticated.value = true;
					this.authenticated = true;
				}
				this.loading = false;
			}
			catch (error: any) {
				this.$state.errors = ['An error occurred. Please try again later.'];
				console.log(error);
			}
			this.loading = false;
		},

		async getProvider() {
			const { $api } = useNuxtApp();
			try {
				const response = await $api.auth.provider();
				if (response?.data) {
					this.provider = response.data;
				}
			}
			catch (error: any) {
				// Provider lookup failures are non-fatal: fall back to local
				// login when the endpoint is unreachable so a misconfigured
				// auth-provider route doesn't lock everyone out.
				console.warn('[auth] provider lookup failed', error);
				this.provider = {
					auth_provider: 'built-in',
					settings_uri: '',
					max_token_lifetime: 0,
					local_login_available: true,
				};
			}
		},
		async beginOAuth() {
			const { $api } = useNuxtApp();
			this.loading = true;
			try {
				const response = await $api.auth.oauthSettings();
				if (response?.data?.details?.authorize_url) {
					this.oauthLoginInfo = response.data.details;
					window.location.assign(response.data.details.authorize_url);
					return;
				}
				this.errors = ['OAuth provider returned no authorize_url'];
			}
			catch (error: any) {
				console.error('[auth] oauth settings failed', error);
				this.errors = ['Could not start OIDC sign-in. Please try again or use local login.'];
			}
			finally {
				this.loading = false;
			}
		},
		async exchangeOAuthCode(code: string, state: string, tokenLifetime: string = '3600') {
			const { $api } = useNuxtApp();
			this.loading = true;
			const token = useCookie<string>('token');
			const is_authenticated = useCookie<boolean>('is_authenticated');
			try {
				const response = await $api.auth.oauthLogin(code, state, tokenLifetime);
				if (response?.data?.token) {
					if (response.data.two_fa !== null) {
						this.twoFaToken = response.data.token;
						this.two_fa = response.data.two_fa;
						this.showTwoFa = true;
					}
					else {
						token.value = response.data.token;
						is_authenticated.value = true;
						this.authenticated = true;
					}
				}
			}
			catch (error: any) {
				if (error.response?.data?.errors?.length > 0) {
					const e = error.response.data.errors[0];
					this.errors = [e.detail || e.title || 'OIDC login failed'];
				}
				else {
					this.errors = ['OIDC login failed. Please try again.'];
				}
			}
			finally {
				this.loading = false;
			}
		},
		logOut() {
			const token = useCookie('token');
			const is_authenticated = useCookie<boolean>('is_authenticated');
			this.authenticated = false;
			token.value = null;
			is_authenticated.value = false;
		},
	},
});
