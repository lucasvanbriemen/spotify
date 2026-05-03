<script>
  import { onMount } from 'svelte';
  import { openContextMenu } from '../stores/context_menu.svelte.js';
  import { playlistItems, playlistSongItems } from '../lib/menus.js';
  import { navigate } from '../stores/router.svelte.js';
  import '../../scss/playlist.scss';

  let playlist = $state({ songs: [] });
  let { id } = $props();

  onMount(loadPlaylist);

  async function loadPlaylist() {
    playlist = await api.get(route('playlist.show', { playlist: id }));
  }
</script>

<main class="playlist-page">
  <header
    class="playlist-header"
    oncontextmenu={(e) =>
      playlist.id &&
      openContextMenu(
        e,
        playlistItems(playlist, {
          onChanged: () => loadPlaylist(),
          onDeleted: () => navigate('/'),
        })
      )}
    role="presentation"
  >
    <img src={playlist.image_url} alt={playlist.name} />
    <h1>{playlist.name}</h1>
  </header>

  <ul class="songs">
    {#each playlist.songs ?? [] as song}
      <li
        class="song"
        oncontextmenu={(e) =>
          openContextMenu(
            e,
            playlistSongItems(playlist, song, { onChanged: () => loadPlaylist() })
          )}
        role="presentation"
      >
        <img src={song.image_url} alt={song.name} />
        <div class="info">
          <span class="title">{song.name}</span>
          <span class="artist">{song.artist}</span>
        </div>
      </li>
    {/each}
  </ul>
</main>
