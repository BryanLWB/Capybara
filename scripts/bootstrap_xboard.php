<?php

declare(strict_types=1);

use App\Console\Commands\XboardInstall;
use App\Models\User;
use App\Services\Plugin\PluginManager;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\Artisan;

require '/www/vendor/autoload.php';

$app = require '/www/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$adminAccount = trim((string) getenv('BOOTSTRAP_ADMIN_ACCOUNT'));

if ($adminAccount === '') {
    fwrite(STDERR, "Missing BOOTSTRAP_ADMIN_ACCOUNT.\n");
    exit(1);
}

function upsertEnv(string $key, string $value): void
{
    $envPath = app()->environmentFilePath();
    $contents = file_exists($envPath) ? file_get_contents($envPath) : '';
    $line = sprintf('%s=%s', strtoupper($key), $value);

    if ($contents === false) {
        throw new RuntimeException("Failed to read env file: {$envPath}");
    }

    if (preg_match('/^' . preg_quote(strtoupper($key), '/') . '=[^\r\n]*/m', $contents)) {
        $contents = preg_replace(
            '/^' . preg_quote(strtoupper($key), '/') . '=[^\r\n]*/m',
            $line,
            $contents
        );
    } else {
        $contents = rtrim($contents, "\r\n") . PHP_EOL . $line . PHP_EOL;
    }

    if (file_put_contents($envPath, $contents) === false) {
        throw new RuntimeException("Failed to update env file: {$envPath}");
    }
}

try {
    Artisan::call('config:clear');
    Artisan::call('cache:clear');

    if (trim((string) env('APP_KEY', '')) === '') {
        Artisan::call('key:generate', ['--force' => true]);
    }

    Artisan::call('migrate', ['--force' => true]);

    $user = User::byEmail($adminAccount)->first();
    if (!$user) {
        $temporaryPassword = bin2hex(random_bytes(8));
        if (!XboardInstall::registerAdmin($adminAccount, $temporaryPassword)) {
            throw new RuntimeException("Failed to create admin account: {$adminAccount}");
        }
    } elseif (!$user->is_admin) {
        $user->is_admin = 1;
        if (!$user->save()) {
            throw new RuntimeException("Failed to promote admin account: {$adminAccount}");
        }
    }

    XboardInstall::restoreProtectedPlugins();
    PluginManager::installDefaultPlugins();
    upsertEnv('INSTALLED', '1');

    fwrite(STDOUT, json_encode([
        'status' => 'ok',
        'admin_account' => $adminAccount,
    ], JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    fwrite(STDERR, "Bootstrap failed: {$e->getMessage()}\n");
    exit(1);
}
