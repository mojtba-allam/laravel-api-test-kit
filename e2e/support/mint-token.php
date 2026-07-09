<?php

/**
 * Backward-compatible wrapper — delegates to the configured mint-token adapter.
 * Prefer: scripts/adapters/{your-app}/mint-token.php
 */

declare(strict_types=1);

$kitRoot = dirname(__DIR__, 2);
$adapter = $kitRoot.'/scripts/adapters/generic/mint-token.php';

if (is_file($kitRoot.'/config/test.env')) {
    foreach (file($kitRoot.'/config/test.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#') || ! str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = array_map('trim', explode('=', $line, 2));
        if ($key === 'MINT_TOKEN_SCRIPT' && $value !== '') {
            $adapter = str_starts_with($value, '/') ? $value : $kitRoot.'/'.$value;
            break;
        }
    }
}

array_shift($argv);
passthru('php '.escapeshellarg($adapter).' '.implode(' ', array_map('escapeshellarg', $argv)));
