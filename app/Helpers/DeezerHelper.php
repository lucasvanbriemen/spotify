<?php

namespace App\Helpers;

class DeezerHelper {
  private const BASE_URL = 'https://api.deezer.com';

  public static function search($query) {
    $tracks = self::makeRequest("/search/track", ["q" => $query])["data"];
    $playlists = self::makeRequest("/search/playlist", ["q" => $query])["data"];

    return [
      "tracks" => $tracks,
      "playlists" => $playlists,
    ];
  }

  private static function makeRequest(string $endpoint, array $params = []): array {
    $url = self::BASE_URL . $endpoint;

    foreach ($params as $key => $value) {
      $url .= (str_contains($url, '?') ? '&' : '?') . urlencode($key) . '=' . urlencode($value);
    }
  
    // Get the contents of the URL
    $response = file_get_contents($url);
    if ($response === false) {
      throw new \Exception("Failed to fetch data from Deezer API");
    }

    return json_decode($response, true);
  }
}
