<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';

  let { result } = $props();

  async function playVideo(video) {
    const data = await api.get(`${route('get-mp3')}?id=${encodeURIComponent(video.id)}`);
    if (!data?.stream_url) {
      return;
    }

    currentlyPlaying.set({ ...video, stream_url: data.stream_url });
  }
</script>

<button class="result" onclick={() => playVideo(result)}>{result.title}</button>