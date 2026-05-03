<script>
  import { onMount } from 'svelte';
  import '../../scss/playlist.scss';

  let playlist = $state({});

  let { id } = $props();

  onMount(async () => {
    playlist = await api.get(route('playlist.show', { playlist: id }));
  });
</script>

<div class="header">
  <img src={playlist.image_url} alt={playlist.name} />
  <div class="overlay"></div>
  
  <div class="info">
    <span class="title">{playlist.name}</span>
  </div>
</div>