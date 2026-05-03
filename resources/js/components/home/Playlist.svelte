<script>
  import { openContextMenu } from '../../stores/context_menu.svelte.js';
  import { playlistItems } from '../../lib/menus.js';
  import '../../../scss/home/playlist.scss';

  let { playlist } = $props();
</script>

<a
  href="/playlist/{playlist.id}"
  class="playlist"
  oncontextmenu={(e) => openContextMenu(e, playlistItems(playlist))}
>
  <img src={playlist.image_url} alt={playlist.name} />
  <span>{playlist.name}</span>
</a>
