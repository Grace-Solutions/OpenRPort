<template>
	<div />
</template>

<script lang="ts" setup>
// Landing route. Redirect to /dashboard (Clients view) so users skip the
// previously-shown welcome video and start button.
definePageMeta({
	middleware: [function () {
		return navigateTo('/dashboard', { replace: true });
	}],
});
</script>
