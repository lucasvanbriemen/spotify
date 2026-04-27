<?php

namespace App\Helpers;

class GeneralHelper
{
    public static function formatCurrency($amount, $currency = 'USD')
    {
        return number_format($amount, 2) . ' ' . $currency;
    }

    public static function formatDate($date, $format = 'Y-m-d H:i:s')
    {
        return date($format, strtotime($date));
    }

    public static function generateSlug($text)
    {
        return strtolower(trim(preg_replace('/[^A-Za-z0-9-]+/', '-', $text)));
    }

    public static function isValidEmail($email)
    {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }

    public static function truncateText($text, $limit = 100, $suffix = '...')
    {
        if (strlen($text) > $limit) {
            return substr($text, 0, $limit) . $suffix;
        }
        return $text;
    }
}