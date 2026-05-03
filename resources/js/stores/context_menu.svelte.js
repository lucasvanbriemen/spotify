import { writable } from 'svelte/store';

export const contextMenu = writable({ open: false, x: 0, y: 0, items: [] });

export function openContextMenu(event, items) {
  event.preventDefault();
  if (!items?.length) return;
  contextMenu.set({ open: true, x: event.clientX, y: event.clientY, items });
}

export function closeContextMenu() {
  contextMenu.update((m) => ({ ...m, open: false }));
}
