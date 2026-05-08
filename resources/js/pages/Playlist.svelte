<script>
  import { onMount } from 'svelte';
  import { currentlyPlaying, queue } from '../stores/currently_playing.svelte';
  import '../../scss/playlist.scss';

  let playlist = $state({});

  let { id } = $props();

  onMount(async () => {
    playlist = await api.get(route('playlist.show', { playlist: id }));
    playlist.duration = playlist.songs.reduce((total, song) => total + song.duration_ms, 0);
  });

  function getPlaylistDuration() {
    const minutes = Math.floor(playlist.duration / 60000);
    
    if (minutes >= 60) {
      const hours = Math.floor(minutes / 60);
      const remainingMinutes = minutes % 60;
      return `${hours} hr ${remainingMinutes} min`;
    }

    return `${minutes} min`;
  }

  async function playPlaylist(atIndex = 1) {
    const firstSong = playlist.songs[atIndex];

    currentlyPlaying.set({
      id: firstSong.id,
      artist: firstSong.artist,
      title: firstSong.name,
      thumbnail: firstSong.image_url,
      duration: firstSong.duration_ms,
      isPaused: false,
      stream_url: "http://127.0.0.1:8000/api/audio/" + firstSong.mp3_url,
    });
    
    queue.set(playlist.songs.slice(atIndex + 1));
  }
</script>

{#if playlist.songs}
  <div class="header">
    <img src={playlist.image_url} alt={playlist.name} />
    <div class="overlay"></div>

    <div class="actions-and-info">
      <button class="play-button" onclick={playPlaylist}>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="24" height="24">
          <path d="M8 5v14l11-7z"></path>
        </svg>
      </button>

      <div class="info">
        <span class="title">{playlist.name}</span>
        <span class="details">{playlist.songs.length} songs, {getPlaylistDuration()}</span>
      </div>
    </div>
  </div>

  <div class="songs">
    {#each playlist.songs as song, index}
      <div class="song" onclick={() => playPlaylist(index)}>
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