import App from './App.svelte';
import api from './lib/api.js';
import { mount } from 'svelte';
import theme from './lib/theme.js';

// Initialize theme
theme.init();

// Expose api globally for debugging
window.api = api;

const app = mount(App, {
    target: document.getElementById('app'),
});

export default app;