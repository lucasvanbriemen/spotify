<script>
    import { onMount } from 'svelte';
    import { router, initRouter } from './stores/router.svelte.js';
    import { getAllRoutes } from './stores/routes.svelte.js';
    import api from './lib/api.js';

    let routes = [];

    onMount(() => {
        routes = getAllRoutes();
        initRouter();
    });

    // Expose api for components
    window.api = api;
</script>

{#if router.currentComponent}
    <svelte:component this={router.currentComponent} {...router.params} />
{/if}

<style>
    :global(body) {
        margin: 0;
        padding: 0;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    }

    main {
        padding: 2rem;
        max-width: 1200px;
        margin: 0 auto;
    }
</style>
