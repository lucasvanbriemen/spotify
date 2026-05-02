@php
$routes = collect(Route::getRoutes())
    ->map(fn ($route) => [
        'uri' => $route->uri(),
        'name' => $route->getName(),
        'method' => $route->methods()[0],
    ])
    ->values();
@endphp

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ config('app.name', 'Laravel') }}</title>
    <script>
        window.spotifySdkReady = new Promise((resolve) => {
            window.onSpotifyWebPlaybackSDKReady = resolve;
        });
    </script>
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
    @vite(['resources/js/main.js'])
</head>
<body>
    <script>
        const API_ROUTES = @json($routes);
        const currentDomain = window.location.origin;

        function route(name, params = {}) {
            const route = API_ROUTES.find(r => r.name === name);
            let uri = route.uri;

            for (const [key, value] of Object.entries(params)) {
                const cleanKey = key.startsWith('$') ? key.slice(1) : key;
                uri = uri.replace(`{${cleanKey}}`, encodeURIComponent(value));
            }

            return `/${uri}`;
        }
    </script>

    <div id="app"></div>
</body>
</html>