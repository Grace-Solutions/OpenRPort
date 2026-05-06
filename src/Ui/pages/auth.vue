<template>
	<LoginForm
		v-if="!showTwoFa"
		:provider="provider"
		:auth-mode="authMode"
		@login="handleLogin"
		@oidc="handleOidc"
	/>
	<TwoFa
		v-if="showTwoFa"
		:send_to="store.two_fa?.send_to"
		@code="handleTwoFa"
	/>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue';
import LoginForm from '../components/LoginForm.vue';
import type { AuthMode, ILoginInput } from '~/types';

const store = useTokenStore();
const { authenticated, showTwoFa, provider } = storeToRefs(store);
const router = useRouter();
const config = useRuntimeConfig();
const authMode = ((config.public.authMode as AuthMode | undefined) || 'both');
const credentialsRef = ref<ILoginInput>({
	username: '',
	password: '',
	remember_me: '',
});

definePageMeta({
	layout: 'auth',
});
useHead({
	title: 'Login',
});

onMounted(async () => {
	await store.getProvider();
});

const handleLogin = async (credentials: ILoginInput) => {
	credentialsRef.value = credentials;
	await store.getLoginToken(credentials);
	if (authenticated.value) {
		await router.push('/');
	}
};

const handleTwoFa = async (two_fa: string) => {
	await store.verifyTwoFa(credentialsRef.value, two_fa);
	if (authenticated.value) {
		await router.push('/');
	}
};

const handleOidc = async () => {
	await store.beginOAuth();
};
</script>
