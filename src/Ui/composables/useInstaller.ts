import type { InstallerResponse } from '~/types';

export const useInstaller = () => {
	const { $api } = useNuxtApp();

	const isLoading = ref(false);
	const error = ref<string | null>(null);

	const installers = reactive({
		linux: '',
		windows: '',
		pairing_code: '',
	});

	async function fetchInstaller(params: {
		client_id: string;
		connect_url: string;
		fingerprint: string;
		password: string;
		tags?: string[];
	}, pairingUrl: string) {
		isLoading.value = true;
		error.value = null;

		try {
			const body: Record<string, unknown> = {
				client_id: params.client_id,
				connect_url: params.connect_url,
				fingerprint: params.fingerprint,
				password: params.password,
			};
			if (params.tags && params.tags.length > 0) {
				body.tags = params.tags;
			}
			const response = await $fetch<InstallerResponse>(pairingUrl, {
				method: 'POST',
				body,
			});

			Object.assign(installers, {
				linux: response.installers.linux,
				windows: response.installers.windows,
				pairing_code: response.pairing_code,
			});
		}
		catch (e) {
			error.value = e instanceof Error ? e.message : 'Failed to get pairing code';
		}
		finally {
			isLoading.value = false;
		}
	}

	return {
		isLoading,
		error,
		installers,
		fetchInstaller,
	};
};
