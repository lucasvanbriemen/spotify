<script>
    import { searchQuery } from '../stores/search_query.svelte.js';
    let error = $state(null);
    let youtubeResults = $state([]);
    let searching = $state(false);
    let activeVideo = $state(null);

    let searchTimer = null;

    async function playVideo(video) {
        error = null;
        try {
            const data = await api.get(`${route('youtube.audio')}?id=${encodeURIComponent(video.id)}`);
            if (!data?.stream_url) {
                error = data?.detail || data?.error || 'Could not load audio';
                return;
            }
            activeVideo = { ...video, stream_url: data.stream_url };
        } catch (e) {
            error = e.message;
        }
    }

    async function runSearch(q) {
        if (!q.trim()) {
            spotifyResults = [];
            youtubeResults = [];
            searching = false;
            return;
        }
        searching = true;
        const [youtubeRes] = await Promise.allSettled([
            api.get(`${route('youtube.search')}?q=${encodeURIComponent(q)}`),
        ]);
        if (youtubeRes.status === 'fulfilled') {
            youtubeResults = youtubeRes.value?.items ?? [];
        } else {
            error = youtubeRes.reason?.message ?? 'YouTube search failed';
        }
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

        {#if activeVideo}
            <div class="video-player">
                <strong>{activeVideo.title}</strong>
                <span class="artists">{activeVideo.channel}</span>
                <audio src={activeVideo.stream_url} autoplay controls></audio>
                <button class="btn" onclick={() => activeVideo = null}>Close</button>
            </div>
        {/if}

    {#if error}
        <p class="error">{error}</p>
    {/if}
</main>
