<?php

/**
 * Laravel modular app adapter — mint a Sanctum token for API/E2E tests.
 *
 * For applications using nwidart/laravel-modules style structure.
 * Customize model namespaces and role logic for your modules.
 *
 * CLI:
 *   php mint-token.php --email=user@test.example.com [--admin] [--json]
 */

declare(strict_types=1);

$options = getopt('', ['email:', 'admin', 'json', 'name:']);
$email = $options['email'] ?? ('api-test-'.time().'-'.bin2hex(random_bytes(4)).'@test.example.com');
$makeAdmin = array_key_exists('admin', $options);
$name = $options['name'] ?? ('API '.explode('@', $email)[0]);
$jsonMode = array_key_exists('json', $options);

// ── CUSTOMIZE: module model namespaces ─────────────────────────────────────
$userModel = getenv('USER_MODEL') ?: 'Modules\\User\\Models\\User';
$globalRoleModel = getenv('GLOBAL_ROLE_MODEL') ?: 'Modules\\Project\\Models\\GlobalRole';
$adminRoleName = getenv('ADMIN_ROLE_NAME') ?: 'Super Admin';

$testKitRoot = dirname(__DIR__, 3);
$projectRoot = getenv('PROJECT_ROOT') ?: null;

if (! $projectRoot && is_file($testKitRoot.'/config/test.env')) {
    foreach (file($testKitRoot.'/config/test.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#') || ! str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = array_map('trim', explode('=', $line, 2));
        if ($key === 'PROJECT_ROOT' && $value !== '') {
            $projectRoot = $value;
            break;
        }
    }
}

if (! $projectRoot || ! is_file($projectRoot.'/artisan')) {
    fwrite(STDERR, "ERROR: PROJECT_ROOT not set or invalid.\n");
    exit(1);
}

require $projectRoot.'/vendor/autoload.php';

$app = require $projectRoot.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Hash;

/** @var \Illuminate\Database\Eloquent\Model $user */
$user = $userModel::firstOrCreate(
    ['email' => $email],
    [
        'name' => $name,
        'password' => Hash::make('TestPass123!'),
        'email_verified_at' => now(),
        'is_active' => true,
    ]
);

$changed = false;
if (! $user->email_verified_at) {
    $user->email_verified_at = now();
    $changed = true;
}
if (isset($user->is_active) && ! $user->is_active) {
    $user->is_active = true;
    $changed = true;
}
if ($changed) {
    $user->save();
}

if ($makeAdmin || stripos($email, 'admin') !== false) {
    $role = $globalRoleModel::firstOrCreate(
        ['name' => $adminRoleName],
        ['description' => 'System administrator', 'is_system_role' => true]
    );
    if (method_exists($user, 'systemRoles')) {
        $user->systemRoles()->syncWithoutDetaching([$role->id]);
    }
}

$token = $user->createToken('api-test')->plainTextToken;

if ($jsonMode) {
    echo json_encode([
        'token' => $token,
        'userId' => $user->id,
        'email' => $email,
    ], JSON_THROW_ON_ERROR);
} else {
    echo '__UID__'.$user->id.'__TOK__'.$token.'__END__';
}
