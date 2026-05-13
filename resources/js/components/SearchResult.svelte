<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import { openContextMenu } from '../stores/context_menu.svelte.js';
  import { addToPlaylistItems } from '../lib/menus.js';
  import '../../scss/search_result.scss';

  let { result } = $props();

  function playVideo(video) {
    currentlyPlaying.set({
      ...video,
      stream_url: route('get-mp3-url', { song_id: video.file_id }),
    });
  }
</script>

<button class="result" onclick={() => playVideo(result)} oncontextmenu={(e) => openContextMenu(e, addToPlaylistItems(result))}>
  <img src={result.thumbnail} alt={result.title} />
  <div class="info">
    <span class="title">{result.title}</span>
    <span class="artist">{result.artist}</span>
  </div>
</button>