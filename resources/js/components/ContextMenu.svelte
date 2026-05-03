<script>
  import { onMount } from 'svelte';
  import { contextMenu, closeContextMenu } from '../stores/context_menu.svelte.js';
  import '../../scss/context_menu.scss';

  let menuEl = $state(null);
  let position = $state({ x: 0, y: 0 });

  $effect(() => {
    if (!contextMenu.open) return;
    position = { x: contextMenu.x, y: contextMenu.y };
    queueMicrotask(() => {
      if (!menuEl) return;
      const rect = menuEl.getBoundingClientRect();
      const overflowX = rect.right - window.innerWidth;
      const overflowY = rect.bottom - window.innerHeight;
      position = {
        x: overflowX > 0 ? Math.max(8, contextMenu.x - overflowX - 8) : contextMenu.x,
        y: overflowY > 0 ? Math.max(8, contextMenu.y - overflowY - 8) : contextMenu.y,
      };
    });
  });

  function onDocMouseDown(e) {
    if (!contextMenu.open) return;
    if (menuEl && menuEl.contains(e.target)) return;
    closeContextMenu();
  }

  function onDocContextMenu(e) {
    if (!contextMenu.open) return;
    if (menuEl && menuEl.contains(e.target)) return;
    closeContextMenu();
  }

  async function pick(item) {
    closeContextMenu();
    await item.onSelect?.();
  }

  onMount(() => {
    document.addEventListener('mousedown', onDocMouseDown);
    document.addEventListener('contextmenu', onDocContextMenu, true);
    window.addEventListener('blur', closeContextMenu);
    window.addEventListener('resize', closeContextMenu);
    return () => {
      document.removeEventListener('mousedown', onDocMouseDown);
      document.removeEventListener('contextmenu', onDocContextMenu, true);
      window.removeEventListener('blur', closeContextMenu);
      window.removeEventListener('resize', closeContextMenu);
    };
  });
</script>

{#if contextMenu.open}
  <div class="context-menu" bind:this={menuEl} style="left: {position.x}px; top: {position.y}px;">
    {#each contextMenu.items as item}
      {#if item.type === 'header'}
        <div class="header">{item.label}</div>
      {:else}
        <button class="item" onclick={() => pick(item)}>
          <img src={item.image_url} alt="" />
          <span>{item.label}</span>
        </button>
      {/if}
    {/each}
  </div>
{/if}
