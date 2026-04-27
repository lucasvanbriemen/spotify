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

<nav>
    {#each routes as route (route.path)}
        <a href={route.path}>{route.name}</a>
    {/each}
</nav>

<main>
    {#if router.currentComponent}
        <svelte:component this={router.currentComponent} {...router.params} />
    {/if}
</main>

<style>
    :global(body) {
        margin: 0;
        padding: 0;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    }

    nav {
        background-color: #333;
        padding: 1rem;
        margin-bottom: 2rem;
    }

    nav a {
        color: white;
        text-decoration: none;
        margin-right: 1rem;
        padding: 0.5rem 1rem;
        border-radius: 4px;
        transition: background-color 0.3s;
    }

    nav a:hover {
        background-color: #555;
    }

    main {
        padding: 2rem;
        max-width: 1200px;
        margin: 0 auto;
    }
</style>
