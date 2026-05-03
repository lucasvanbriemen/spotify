<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import '../../scss/search_result.scss';

  let { result } = $props();

  async function playVideo(video) {
    const data = await api.get(`${route('get-mp3-url')}?id=${encodeURIComponent(video.id)}`);
    if (!data?.stream_url) {
      return;
    }

    currentlyPlaying.set({ ...video, stream_url: data.stream_url });
  }
</script>

<button class="result" onclick={() => playVideo(result)}>
  <img src={result.thumbnail} alt={result.title} />
  <div class="info">
    <span class="title">{result.title}</span>
    <span class="artist">{result.artist}</span>
  </div>
</button>