import { playlistsState } from '../stores/playlists.svelte.js';

export function songData(track) {
  return {
    spotify_id: track.id,
    name: track.title,
    artist: track.artist,
    album: track.album,
    image_url: track.thumbnail,
    duration_ms: (track.duration ?? 0) * 1000,
  };
}

export function addToPlaylistItems(song) {
  return [
    { 
      type: 'header', 
      label: 'Add to playlist' 
    },
    ...playlistsState.list.map((p) => ({
      type: 'item',
      label: p.name,
      image_url: p.image_url,
      onSelect: () =>
        window.api.post(route('playlist.songs.store', { playlist: p.id }), songData(song)),
    })),
  ];
}
