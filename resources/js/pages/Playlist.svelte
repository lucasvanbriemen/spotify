<script>
  import { onMount } from 'svelte';
  import '../../scss/playlist.scss';

  let playlist = $state({});

  let { id } = $props();

  onMount(async () => {
    playlist = await api.get(route('playlist.show', { playlist: id }));
    playlist.duration = playlist.songs.reduce((total, song) => total + song.duration_ms, 0);
  });
</script>

{#if playlist.songs}
  <div class="header">
    <img src={playlist.image_url} alt={playlist.name} />
    <div class="overlay"></div>

    <div class="info">
      <span class="title">{playlist.name}</span>
      <span class="details">{playlist.songs.length} songs, {Math.floor(playlist.duration / 60000)} min</span>
    </div>
  </div>

  <div class="songs">
    {#each playlist.songs as song}
      <div class="song">
        <img src={song.image_url} alt={song.name} />
        <div class="info">
          <span class="title">{song.name}</span>

          <div class="secondary">
            <span class="artist">{song.artist}</span>
            <span class="separator"></span>
            <span class="artist">{song.album}</span>
            <span class="separator"></span>
            <span class="duration">{Math.floor(song.duration_ms / 60000)}:{Math.floor((song.duration_ms % 60000) / 1000).toString().padStart(2, '0')}</span>
          </div>
        </div>
      </div>
    {/each}
  </div>
{/if}