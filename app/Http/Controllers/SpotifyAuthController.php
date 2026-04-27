<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class SpotifyAuthController extends Controller
{
    private const SCOPES = 'streaming user-read-email user-read-private user-modify-playback-state user-read-playback-state';

    public function redirect(Request $request): RedirectResponse
    {
        $state = Str::random(32);
        $request->session()->put('spotify_oauth_state', $state);

        $query = http_build_query([
            'response_type' => 'code',
            'client_id' => config('services.spotify.client_id'),
            'scope' => self::SCOPES,
            'redirect_uri' => config('services.spotify.redirect_uri'),
            'state' => $state,
        ]);

        return redirect('https://accounts.spotify.com/authorize?' . $query);
    }

    public function callback(Request $request): RedirectResponse
    {
        if ($request->filled('error')) {
            return redirect('/')->with('spotify_error', $request->string('error'));
        }

        $expectedState = $request->session()->pull('spotify_oauth_state');
        if (! $expectedState) {
            return redirect('/auth/spotify')->with(
                'spotify_error',
                'Session state missing — make sure you opened the app at the same host registered in Spotify (use http://127.0.0.1:8000, not localhost).'
            );
        }
        if ($request->string('state')->value() !== $expectedState) {
            abort(400, 'Invalid OAuth state');
        }

        $response = Http::asForm()->post('https://accounts.spotify.com/api/token', [
            'grant_type' => 'authorization_code',
            'code' => $request->string('code')->value(),
            'redirect_uri' => config('services.spotify.redirect_uri'),
            'client_id' => config('services.spotify.client_id'),
            'client_secret' => config('services.spotify.client_secret'),
        ]);

        if ($response->failed()) {
            abort(500, 'Spotify token exchange failed: ' . $response->body());
        }

        $this->storeToken($request, $response->json());

        return redirect('/');
    }

    public function token(Request $request): JsonResponse
    {
        $token = $request->session()->get('spotify_token');

        if (! $token) {
            return response()->json(['authenticated' => false]);
        }

        if (now()->timestamp >= ($token['expires_at'] - 30)) {
            $token = $this->refresh($request, $token['refresh_token']);
            if (! $token) {
                return response()->json(['authenticated' => false]);
            }
        }

        return response()->json([
            'authenticated' => true,
            'access_token' => $token['access_token'],
            'expires_at' => $token['expires_at'],
        ]);
    }

    public function logout(Request $request): RedirectResponse
    {
        $request->session()->forget('spotify_token');
        return redirect('/');
    }

    private function refresh(Request $request, string $refreshToken): ?array
    {
        $response = Http::asForm()->post('https://accounts.spotify.com/api/token', [
            'grant_type' => 'refresh_token',
            'refresh_token' => $refreshToken,
            'client_id' => config('services.spotify.client_id'),
            'client_secret' => config('services.spotify.client_secret'),
        ]);

        if ($response->failed()) {
            $request->session()->forget('spotify_token');
            return null;
        }

        $payload = $response->json();
        $payload['refresh_token'] = $payload['refresh_token'] ?? $refreshToken;

        return $this->storeToken($request, $payload);
    }

    private function storeToken(Request $request, array $payload): array
    {
        $token = [
            'access_token' => $payload['access_token'],
            'refresh_token' => $payload['refresh_token'] ?? $request->session()->get('spotify_token.refresh_token'),
            'expires_at' => now()->timestamp + ($payload['expires_in'] ?? 3600),
        ];
        $request->session()->put('spotify_token', $token);
        return $token;
    }
}
