import { writable } from 'svelte/store';

export const currentlyPlaying = writable({
  title: '',
  artist: '',
  album: '',

  thumbnail: '',
  duration: 0,
  position: 0,
  isPaused: false,
  stream_url: '',
});