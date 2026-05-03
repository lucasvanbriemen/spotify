<script>
  import '../../../scss/home/playlist.scss';

  let { playlist } = $props();
</script>

<a href="/playlist/{playlist.id}" class="playlist">
  <img src={playlist.image_url} alt={playlist.name} />
  <span>{playlist.name}</span>
</a>
