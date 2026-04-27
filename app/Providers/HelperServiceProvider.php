<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use App\Helpers\GeneralHelper;

class HelperServiceProvider extends ServiceProvider
{
    public function register()
    {
        //
    }

    public function boot()
    {
        $this->registerHelperFunctions();
    }

    private function registerHelperFunctions()
    {
        $helperClasses = [
            GeneralHelper::class,
        ];

        foreach ($helperClasses as $class) {
            if (class_exists($class)) {
                $methods = get_class_methods($class);
                foreach ($methods as $method) {
                    if (strpos($method, '__') !== 0) {
                        $functionName = strtolower(preg_replace('/(?<!^)[A-Z]/', '_$0', $method));
                        if (!function_exists($functionName)) {
                            eval("function {$functionName}(...\$args) { return {$class}::{$method}(...\$args); }");
                        }
                    }
                }
            }
        }
    }
}