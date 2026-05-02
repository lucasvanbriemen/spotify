import { writable } from 'svelte/store';

export const currentlyPlaying = writable({
  title: 'Poison',
  artist: 'Alice Cooper',
  album: 'Trash',

  thumbnail: '',
  duration: (60  * 4) + 29, // 4:29
  position: 0,
  isPaused: false,
  stream_url: '',
});