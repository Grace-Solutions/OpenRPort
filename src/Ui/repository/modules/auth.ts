import type { FetchOptions } from 'ofetch';
import { HttpFactory } from '~/repository/factory';
import type {
	ApiLoginResponse,
	AuthProviderResponse,
	AuthSettingsResponse,
	ILoginInput,
} from '~/types';

class AuthModule extends HttpFactory {
	private RESOURCE = '/api/v1/login';

	async login(credentials: ILoginInput): Promise<ApiLoginResponse> {
		const token = btoa(`${credentials.username}:${credentials.password}`);
		const fetchOptions: FetchOptions<'json'> = {
			headers: {
				'Authorization': `Basic ${token}`,
				'Content-Type': 'application/json',
			},
		};
		return this.call<ApiLoginResponse>(
			'GET',
			`${this.RESOURCE}?token-lifetime=${credentials.remember_me}`,
			undefined,
			fetchOptions,
		);
	}

	async provider(): Promise<AuthProviderResponse> {
		return this.call<AuthProviderResponse>(
			'GET',
			'/api/v1/auth/provider',
			undefined,
		);
	}

	async oauthSettings(): Promise<AuthSettingsResponse> {
		return this.call<AuthSettingsResponse>(
			'GET',
			'/api/v1/auth/ext/settings',
			undefined,
		);
	}

	async oauthLogin(code: string, state: string, tokenLifetime: string): Promise<ApiLoginResponse> {
		const params = new URLSearchParams();
		if (code) params.set('code', code);
		if (state) params.set('state', state);
		if (tokenLifetime) params.set('token-lifetime', tokenLifetime);
		return this.call<ApiLoginResponse>(
			'GET',
			`/api/v1/oauth/login?${params.toString()}`,
			undefined,
		);
	}

	async logout(token: string): Promise<any> {
		const fetchOptions: FetchOptions<'json'> = {
			headers: {
				'Authorization': `Bearer ${token}`,
				'Content-Type': 'application/json',
			},
		};
		return this.call<any>(
			'DELETE',
			'/api/v1/logout',
			undefined,
			fetchOptions,
		);
	}

	async verify2fa(credentials: ILoginInput, token: string, twofaToken: string): Promise<ApiLoginResponse> {
		const fetchOptions: FetchOptions<'json'> = {
			headers: {
				'Authorization': `Bearer ${token}`,
				'Content-Type': 'application/json',
			},
		};
		return this.call<ApiLoginResponse>(
			'POST',
			`/api/v1/verify-2fa?token-lifetime=${credentials.remember_me}`,
			{
				username: credentials.username,
				token: twofaToken,
			},
			fetchOptions,
		);
	}
}

export default AuthModule;
