<?php

/**
 * Generic Laravel + Sanctum adapter template.
 *
 * Customize the model namespace and optional admin role logic for your app.
 * Copy to scripts/adapters/your-app/mint-token.php and point MINT_TOKEN_SCRIPT at it.
 *
 * CLI:
 *   php mint-token.php --email=user@test.example.com [--admin] [--json]
 */

declare(strict_types=1);

$options = getopt('', ['email:', 'admin', 'json', 'name:']);
$email = $options['email'] ?? ('api-test-'.time().'-'.bin2hex(random_bytes(4)).'@test.example.com');
$makeAdmin = array_key_exists('admin', $options);
$name = $options['name'] ?? ('API Test User');
$jsonMode = array_key_exists('json', $options);

// ── CUSTOMIZE: your User model FQCN ──────────────────────────────────────
$userModel = App\Models\User::class;

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
    ]
);

if (property_exists($user, 'is_active') || array_key_exists('is_active', $user->getAttributes())) {
    if (! $user->is_active) {
        $user->is_active = true;
        $user->save();
    }
}

if (! $user->email_verified_at) {
    $user->email_verified_at = now();
    $user->save();
}

// ── CUSTOMIZE: grant admin role if your app uses roles ─────────────────────
if ($makeAdmin) {
    // Example: $user->assignRole('admin');
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
