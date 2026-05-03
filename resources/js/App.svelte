<script>
    import { onMount } from 'svelte';
    import { router, initRouter } from './stores/router.svelte.js';
    import Header from './components/Header.svelte';
    import Player from './components/Player.svelte';
    import api from './lib/api.js';

    onMount(() => {
        initRouter();
    });

    window.api = api;
</script>

<Header />

{#if router.currentComponent}
    <svelte:component this={router.currentComponent} {...router.params} />
{/if}

<Player />

<style>
    :global(body) {
        margin: 0;
        padding: 0;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
        background-color: var(--background-color);
        color: var(--text-color-secondary);
        transition: all 0.3s ease-in-out;

        min-height: 100vh;
    }

    * {
        transition: all 0.3s ease-in-out !important;
    }
</style>
