<script>
  import { playFromQueue } from '../stores/queue.svelte.js';
  import { openContextMenu } from '../stores/context_menu.svelte.js';
  import { addToPlaylistItems } from '../lib/menus.js';
  import '../../scss/search_result.scss';

  let { result } = $props();
</script>

<button class="result" onclick={() => playFromQueue([result], 0, { autoExtend: true })} oncontextmenu={(e) => openContextMenu(e, addToPlaylistItems(result))}>
  <img src={result.thumbnail} alt={result.title} />
  <div class="info">
    <span class="title">{result.title}</span>
    <span class="artist">{result.artist}</span>
  </div>
</button>
