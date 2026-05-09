<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import { openContextMenu } from '../stores/context_menu.svelte.js';
  import { addToPlaylistItems } from '../lib/menus.js';
  import '../../scss/search_result.scss';

  let { result } = $props();

  async function playVideo(video) {
    const data = await api.get(route('get-mp3-url', {song_id: video.id}));
    if (!data?.stream_url) {
      return;
    }

    currentlyPlaying.set({ ...video, stream_url: data.stream_url });
  }
</script>

<button class="result" onclick={() => playVideo(result)} oncontextmenu={(e) => openContextMenu(e, addToPlaylistItems(result))}>
  <img src={result.thumbnail} alt={result.title} />
  <div class="info">
    <span class="title">{result.title}</span>
    <span class="artist">{result.artist}</span>
  </div>
</button>