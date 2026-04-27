import Home from '../pages/Home.svelte';

export const ROUTES = {
  home: {
    path: '/',
    component: Home,
    name: 'Home',
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
