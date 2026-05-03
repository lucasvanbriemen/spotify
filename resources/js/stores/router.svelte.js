import Home from '../pages/Home.svelte';
import Playlist from '../pages/Playlist.svelte';

const routes = compile([
    { path: '/', component: Home },
    { path: '/playlist/:id', component: Playlist },
]);

function compile(defs) {
    return defs.map(({ path, component }) => {
        const keys = [];
        const pattern = new RegExp(
            '^' + path.replace(/:([^/]+)/g, (_, k) => (keys.push(k), '([^/]+)')) + '$'
        );
        return { pattern, keys, component };
    });
}

export const router = $state({
    currentComponent: Home,
    params: {},
});

function match(pathname) {
    for (const r of routes) {
        const m = pathname.match(r.pattern);
        if (m) {
            const params = {};
            r.keys.forEach((k, i) => (params[k] = m[i + 1]));
            return { component: r.component, params };
        }
    }
    return null;
}

function navigate(pathname, push = true) {
    const hit = match(pathname);
    if (!hit) {
        window.location.href = pathname;
        return;
    }
    if (push) history.pushState({}, '', pathname);
    router.currentComponent = hit.component;
    router.params = hit.params;
}

export function initRouter() {
    document.addEventListener('click', (e) => {
        const a = e.target.closest('a[href]');
        if (!a) return;
        if (a.target && a.target !== '_self') return;
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        let url;
        try { url = new URL(a.href, location.origin); } catch { return; }
        if (url.origin !== location.origin) return;
        if (!match(url.pathname)) return;
        e.preventDefault();
        navigate(url.pathname);
    });

    window.addEventListener('popstate', () => navigate(location.pathname, false));
    navigate(location.pathname, false);
}
