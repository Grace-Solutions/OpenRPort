interface ClientAuth {
	id: string;
	password: string;
	tags?: string[];
}

export const useClientAccess = () => {
	const { $api } = useNuxtApp();

	const createClientAccess = async (data: { id: string; password: string; tags?: string[] }) => {
		const authClient: ClientAuth = {
			id: data.id,
			password: data.password,
		};
		if (data.tags && data.tags.length > 0) {
			authClient.tags = data.tags;
		}
		await $api.clientAuth.create(authClient);
		return true;
	};

	return {
		createClientAccess,
	};
};
