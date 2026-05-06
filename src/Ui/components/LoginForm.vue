<template>
	<form
		class="w-full max-w-[400px]"
		autocomplete="off"
		novalidate
		@submit.prevent="login"
	>
		<h1 class="pb-6 text-3xl">
			Login
		</h1>

		<!-- Top-level error banner. Rendered outside the basic-form wrapper so
		     OIDC start failures are still visible in oidc-only mode. -->
		<div
			v-show="errors.length > 0"
			class="mb-4 rounded p-2.5 bg-red-50"
		>
			<div class="flex items-center">
				<div class="ml-3 flex-grow">
					<p class="text-sm font-medium text-red-800">
						{{ errorMessage }}
					</p>
				</div>
			</div>
		</div>

		<!-- OIDC button: shown when provider is non-built-in and the
		     effective mode permits it. Rendered above the basic form so
		     it's the obvious primary path when both are available. -->
		<div
			v-if="showOidc"
			class="mb-4"
		>
			<button
				type="button"
				class="hover:opacity-80 px-6 py-3 w-full text-sm text-white rounded inline-flex items-center justify-center duration-200 focus:outline-none bg-primary"
				@click.prevent="emitOidc"
			>
				Sign in with {{ providerLabel }}
			</button>
		</div>

		<div
			v-if="showOidc && showBasic"
			class="my-4 flex items-center"
		>
			<div class="h-px flex-grow bg-theme-border" />
			<span class="mx-3 text-xs text-theme-label">or</span>
			<div class="h-px flex-grow bg-theme-border" />
		</div>

		<div v-if="showBasic">
			<div class="flex flex-col">
				<div class="relative mt-1 flex w-full flex-col">
					<input
						id="username"
						v-model="user.username"
						name="username"
						type="email"
						class="primary block p-2.5 input-text focus:border-1 peer order-2 block h-10 w-full rounded bg-transparent text-theme-inverted shadow-sm focus:outline-primary-50 focus:ring-0 sm:text-sm"
						autocomplete="off"
						required
					>
					<label
						for="username"
						class="order-1 flex pb-1 pl-1 text-theme-label peer-focus:text-blue text-sm font-normal"
					>Username</label>
				</div>
			</div>
			<div class="flex flex-col mt-2">
				<div class="relative mt-1 flex w-full flex-col">
					<input
						id="password"
						v-model="user.password"
						name="password"
						type="password"
						class="primary block p-2.5 input-text focus:border-1 peer order-2 block h-10 w-full rounded bg-transparent text-theme-inverted shadow-sm focus:outline-0 focus:ring-0 sm:text-sm"
						autocomplete="off"
						required
					>
					<label
						for="password"
						class="order-1 flex pb-1 pl-1 text-theme-label peer-focus:text-primary text-sm font-normal"
					>Password</label>
				</div>
			</div>
			<div class="mt-2">
				<div class="relative mt-1 flex w-full flex-col">
					<select
						id="rememberMe"
						v-model="user.remember_me"
						name="rememberMe"
						class="primary p-2.5 focus:border-1 peer order-2 block h-10 w-full rounded border-theme-border bg-transparent shadow-sm focus:outline-0 focus:ring-0 sm:text-sm"
					>
						<option value="" />
						<option :value="3600">
							1 hour
						</option>
						<option :value="3600 * 24">
							24 hours
						</option>
						<option :value="3600 * 24 * 7">
							7 days
						</option>
						<option :value="3600 * 24 * 14">
							14 days
						</option>
						<option :value="3600 * 24 * 30">
							30 days
						</option>
					</select>
					<label
						for="rememberMe"
						class="order-1 flex pb-1 pl-1 text-theme-label peer-focus:text-primary-800 order-1 text-sm font-medium"
					>Remember
						me for</label>
				</div>
			</div>
			<div class="mt-6 flex items-center justify-start">
				<button
					class="hover:opacity-80 px-6 py-3 text-sm text-white rounded inline-flex items-center duration-200 focus:outline-none bg-primary"
					type="submit"
					@click.prevent="login"
				>
					<div
						v-show="loading"
						role="status"
					>
						<svg
							aria-hidden="true"
							class="inline w-6 h-6 text-gray-200 animate-spin dark:text-gray-600 fill-blue-600"
							viewBox="0 0 100 101"
							fill="none"
							xmlns="http://www.w3.org/2000/svg"
						>
							<path
								d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
								fill="currentColor"
							/>
							<path
								d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
								fill="currentFill"
							/>
						</svg>
						<span class="sr-only">Loading...</span>
					</div>
					Login
				</button>
			</div>
		</div>
	</form>

	<!--
                <span class="input-group-text">
                          <a href="#" class="link-secondary" title="Show password" data-bs-toggle="tooltip">-- Download SVG icon from http://tabler-icons.io/i/eye -
    <svg xmlns="http://www.w3.org/2000/svg" class="icon" width="24" height="24" viewBox="0 0 24 24" stroke-width="2"
        stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
        <path d="M10 12a2 2 0 1 0 4 0a2 2 0 0 0 -4 0" />
        <path d="M21 12c-2.4 4 -5.4 6 -9 6c-3.6 0 -6.6 -2 -9 -6c2.4 -4 5.4 -6 9 -6c3.6 0 6.6 2 9 6" />
    </svg>
    </a>
    </span>
    </div>
    </div>
     -->
</template>

<script lang="ts" setup>
import { computed, ref } from 'vue';
import type { AuthMode, AuthProviderInfo, ILoginInput } from '~/types';

const props = defineProps<{
	provider?: AuthProviderInfo | null;
	authMode?: AuthMode;
}>();

const store = useTokenStore();

const { errors, loading } = storeToRefs(store);
const user = ref<ILoginInput>({
	username: 'admin',
	password: '',
	remember_me: '3600',
});
const emit = defineEmits(['login', 'oidc']);
const login = async () => {
	const credentials: ILoginInput = {
		...user.value,
	};
	emit('login', credentials);
};
const emitOidc = () => emit('oidc');

// Resolve which surfaces to render based on operator's UI mode preference
// crossed with what the server actually allows. The server is authoritative
// on availability (see /api/v1/auth/provider), the UI mode is only used to
// hide a path the operator doesn't want offered.
const isBuiltIn = computed(() => !props.provider || props.provider.auth_provider === 'built-in');
const oauthAvailable = computed(() => !!props.provider && !isBuiltIn.value);
const localAvailable = computed(() => !props.provider || props.provider.local_login_available !== false);
const mode = computed<AuthMode>(() => props.authMode || 'both');

const showOidc = computed(() => {
	if (!oauthAvailable.value) return false;
	return mode.value === 'oidc' || mode.value === 'both' || mode.value === 'auto';
});
const showBasic = computed(() => {
	if (!localAvailable.value) return false;
	if (mode.value === 'oidc') return false;
	if (mode.value === 'auto') return !oauthAvailable.value;
	return true;
});

const providerLabel = computed(() => {
	const p = props.provider?.auth_provider;
	if (!p || p === 'built-in' || p === 'oidc') return 'OIDC';
	return p.charAt(0).toUpperCase() + p.slice(1);
});

const errorMessage = computed(() => {
	const e = errors.value as unknown;
	if (Array.isArray(e)) return (e as string[]).join(' ');
	if (typeof e === 'string') return e;
	return 'unauthorized';
});
</script>
