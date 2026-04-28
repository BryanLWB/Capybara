<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;

require '/www/vendor/autoload.php';

$app = require '/www/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$settings = [];

$appName = trim((string) env('APP_NAME', ''));
if ($appName !== '') {
    $settings['app_name'] = $appName;
}

$appUrl = trim((string) env('APP_URL', ''));
if ($appUrl !== '') {
    $settings['app_url'] = $appUrl;
}

$serverWsUrl = trim((string) env('SERVER_WS_URL', ''));
if ($serverWsUrl !== '') {
    $settings['server_ws_url'] = $serverWsUrl;
}

$emailHost = trim((string) env('MAIL_HOST', ''));
if ($emailHost !== '') {
    $settings['email_host'] = $emailHost;
    $settings['email_port'] = (string) env('MAIL_PORT', '');
    $settings['email_encryption'] = (string) env('MAIL_ENCRYPTION', '');
    $settings['email_username'] = (string) env('MAIL_USERNAME', '');
    $settings['email_password'] = (string) env('MAIL_PASSWORD', '');
    $settings['email_from_address'] = (string) env('MAIL_FROM_ADDRESS', '');
}

if ($settings === []) {
    fwrite(STDOUT, "No Xboard settings to sync.\n");
    exit(0);
}

try {
    admin_setting($settings);
    fwrite(STDOUT, json_encode(['status' => 'ok', 'keys' => array_keys($settings)], JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    fwrite(STDERR, "Skipping Xboard settings sync: {$e->getMessage()}\n");
    exit(0);
}
