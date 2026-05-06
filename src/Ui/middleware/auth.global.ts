export default defineNuxtRouteMiddleware((to, from) => {
	// const isLoggedIn = false;
	// if (isLoggedIn) {
	//     return navigateTo(to.fullPath);
	// }
	// return navigateTo("/auth")
	const { authenticated } = storeToRefs(useTokenStore());
	const token = useCookie<string>('token');

	if (token.value) {
		authenticated.value = true;
	}

	const isAuthRoute = to?.name === 'auth' || to?.name === 'auth-callback';

	if (token.value && to?.name === 'auth') {
		return navigateTo('/');
	}
	if (!token.value && !isAuthRoute) {
		abortNavigation();
		return navigateTo('/auth');
	}
});
