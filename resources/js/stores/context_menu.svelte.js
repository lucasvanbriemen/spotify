export const contextMenu = $state({
  open: false,
  x: 0,
  y: 0,
  items: [],
});

export function openContextMenu(event, items) {
  event.preventDefault();
  event.stopPropagation();
  if (!items?.length) return;
  contextMenu.x = event.clientX;
  contextMenu.y = event.clientY;
  contextMenu.items = items;
  contextMenu.open = true;
}

export function closeContextMenu() {
  contextMenu.open = false;
}
