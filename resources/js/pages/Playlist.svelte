<script>
  import { onMount } from 'svelte';
  import '../../scss/playlist.scss';

  let playlist = $state({ songs: [] });
  let { id } = $props();

  onMount(loadPlaylist);

  async function loadPlaylist() {
    playlist = await api.get(route('playlist.show', { playlist: id }));
  }
</script>

<main class="playlist-page">
  <img src={playlist.image_url} alt={playlist.name} />
  <h1>{playlist.name}</h1>
</main>
