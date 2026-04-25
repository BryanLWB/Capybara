<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

require '/www/vendor/autoload.php';

$app = require '/www/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$adminAccount = trim((string) getenv('RESET_ADMIN_ACCOUNT'));
$adminPassword = (string) getenv('RESET_ADMIN_PASSWORD');

if ($adminAccount === '') {
    fwrite(STDERR, "Missing RESET_ADMIN_ACCOUNT.\n");
    exit(1);
}

if (strlen($adminPassword) < 8) {
    fwrite(STDERR, "RESET_ADMIN_PASSWORD must be at least 8 characters.\n");
    exit(1);
}

$user = User::byEmail($adminAccount)->first();

if (!$user) {
    fwrite(STDERR, "Admin account not found: {$adminAccount}\n");
    exit(1);
}

$user->password = password_hash($adminPassword, PASSWORD_DEFAULT);
$user->password_algo = null;
$user->is_admin = 1;

if (!$user->save()) {
    fwrite(STDERR, "Failed to update admin password.\n");
    exit(1);
}

fwrite(STDOUT, json_encode([
    'status' => 'ok',
    'admin_account' => $adminAccount,
], JSON_UNESCAPED_SLASHES) . PHP_EOL);
