<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class IsLoggedIn
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // For testing environment, use mock user
        if (app()->environment('testing')) {
            $current_user = (object) [
                'id' => 1,
                'name' => 'Test User',
                'email' => 'test@example.com',
                'profile_id' => 1,
                'last_activity' => now()->subHours(1)->toDateTimeString(),
            ];
            app()->instance('current_user', $current_user);
            return $next($request);
        }
        
        // Prod only
        if (app()->environment('local')) {
            $authToken = config('app.user_token');
        } else {
            $authToken = $_COOKIE['auth_token'] ?? null;
        }

        $ch = curl_init('https://login.lucasvanbriemen.nl/api/user/token/' . $authToken);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // Prevent direct output
        $responseBody = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode === 200) {
            $current_user = json_decode($responseBody); // Convert JSON to object
            $current_user = $current_user->user;
            app()->instance('current_user', $current_user);

            return $next($request);
        } else {
            return redirect('https://login.lucasvanbriemen.nl?redirect=' . urlencode($request->fullUrl()));
        }
    }
}
