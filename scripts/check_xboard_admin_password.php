<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

require '/www/vendor/autoload.php';

$app = require '/www/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$adminAccount = trim((string) getenv('CHECK_ADMIN_ACCOUNT'));
$adminPassword = (string) getenv('CHECK_ADMIN_PASSWORD');

if ($adminAccount === '') {
    fwrite(STDERR, "Missing CHECK_ADMIN_ACCOUNT.\n");
    exit(1);
}

$user = User::byEmail($adminAccount)->first();
$ok = $user && password_verify($adminPassword, $user->password);

fwrite(STDOUT, $ok ? "ok\n" : "fail\n");
exit($ok ? 0 : 1);
