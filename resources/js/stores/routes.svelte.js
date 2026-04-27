import Home from '../pages/Home.svelte';
import About from '../pages/About.svelte';

export const ROUTES = {
  home: {
    path: '/',
    component: Home,
    name: 'Home',
  },
  about: {
    path: '/about',
    component: About,
    name: 'About',
  },
};

// Get route by path
export function getRoute(path) {
  return Object.values(ROUTES).find(route => route.path === path);
}

// Get all routes
export function getAllRoutes() {
  return Object.values(ROUTES);
}
