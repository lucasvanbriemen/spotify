import { get } from 'svelte/store';
import { playlists, loadPlaylists } from '../stores/playlists.svelte.js';

export function songFromSearchResult(result) {
  return {
    spotify_id: result.id,
    name: result.title,
    artist: result.artist,
    album: result.album,
    image_url: result.thumbnail,
    duration_ms: (result.duration ?? 0) * 1000,
  };
}

export function songFromCurrentlyPlaying(track) {
  if (!track?.id) return null;
  return {
    spotify_id: track.id,
    name: track.title,
    artist: track.artist,
    album: track.album ?? '',
    image_url: track.thumbnail,
    duration_ms: (track.duration ?? 0) * 1000,
  };
}

export function addToPlaylistItems(song) {
  return [
    { type: 'header', label: 'Add to playlist' },
    ...get(playlists).map((p) => ({
      type: 'item',
      label: p.name,
      image_url: p.image_url,
      onSelect: () =>
        window.api.post(route('playlist.songs.store', { playlist: p.id }), song),
    })),
  ];
}

export function songItems(song) {
  return addToPlaylistItems(song);
}

export function playlistSongItems(playlist, song, { onChanged } = {}) {
  return [
    {
      type: 'item',
      label: 'Remove from this playlist',
      danger: true,
      onSelect: async () => {
        await window.api.delete(
          route('playlist.songs.destroy', { playlist: playlist.id, song: song.id })
        );
        onChanged?.();
      },
    },
    { type: 'divider' },
    ...addToPlaylistItems({
      spotify_id: song.mp3_url,
      name: song.name,
      artist: song.artist,
      album: song.album,
      image_url: song.image_url,
      duration_ms: song.duration_ms,
    }),
  ];
}

export function playlistItems(playlist, { onChanged, onDeleted } = {}) {
  return [
    {
      type: 'item',
      label: 'Rename',
      onSelect: async () => {
        const name = window.prompt('New playlist name', playlist.name);
        if (!name || name === playlist.name) return;
        await window.api.patch(route('playlist.update', { playlist: playlist.id }), { name });
        await loadPlaylists();
        onChanged?.();
      },
    },
    {
      type: 'item',
      label: 'Delete playlist',
      danger: true,
      onSelect: async () => {
        if (!window.confirm(`Delete "${playlist.name}"? This cannot be undone.`)) return;
        await window.api.delete(route('playlist.destroy', { playlist: playlist.id }));
        await loadPlaylists();
        (onDeleted ?? onChanged)?.();
      },
    },
  ];
}
