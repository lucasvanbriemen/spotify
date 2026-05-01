<script>
    import { searchQuery } from '../stores/search_query.svelte.js';
    import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
    let youtubeResults = $state([]);
    let searching = $state(false);
    let activeVideo = $state(null);

    let searchTimer = null;

    async function playVideo(video) {
            const data = await api.get(`${route('youtube.audio')}?id=${encodeURIComponent(video.id)}`);
            if (!data?.stream_url) {
                return;
            }
            activeVideo = { ...video, stream_url: data.stream_url };
            currentlyPlaying.set(activeVideo);
    }

    async function runSearch(q) {
        if (!q.trim()) {
            youtubeResults = [];
            searching = false;
            return;
        }
        searching = true;
        const [youtubeRes] = await Promise.allSettled([
            api.get(`${route('youtube.search')}?q=${encodeURIComponent(q)}`),
        ]);
            youtubeResults = youtubeRes.value?.items ?? [];
        searching = false;
    }

    function onQueryInput() {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => runSearch($searchQuery), 250);
    }

</script>

<main>
        <input
            bind:value={$searchQuery}
            oninput={onQueryInput}
            placeholder="Search songs…"
            autocomplete="off"
        />

        {#if searching}
            <p class="muted">Searching…</p>
        {:else}
            {#if youtubeResults.length}
                <h3>Videos</h3>
                {#each youtubeResults as video (video.id)}
                    <button class="result video" onclick={() => playVideo(video)}>
                        {#if video.thumbnail}
                            <img src={video.thumbnail} alt="" />
                        {/if}
                        <span class="meta">
                            <strong>{video.title}</strong>
                            <span class="artists">{video.channel}</span>
                        </span>
                    </button>
                {/each}
            {/if}
        {/if}
</main>
