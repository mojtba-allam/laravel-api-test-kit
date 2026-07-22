<?php

/**
 * Generate Postman Collection v2.1 JSON, environments, and flow collections.
 *
 * Usage (from laravel-api-test-kit root):
 *   cp postman/config.example.php postman/config.php   # once
 *   php postman/generate-collections.php
 *   npm run postman:generate
 *
 * Outputs:
 *   postman/collections/api.json
 *   postman/environments/local.environment.json
 *   postman/flows/flow-*.json
 */

declare(strict_types=1);

$base = __DIR__;
$configPath = is_file($base.'/config.php') ? $base.'/config.php' : $base.'/config.example.php';
/** @var array<string,mixed> $config */
$config = require $configPath;

$collectionsDir = $base.'/collections';
$flowsDir = $base.'/flows';
$envDir = $base.'/environments';
$scriptsDir = $base.'/scripts';

@mkdir($collectionsDir, 0777, true);
@mkdir($flowsDir, 0777, true);
@mkdir($envDir, 0777, true);

foreach (['collection-prerequest.js', 'collection-test.js'] as $f) {
    if (! is_file($scriptsDir.'/'.$f)) {
        fwrite(STDERR, "Missing script: {$scriptsDir}/{$f}\n");
        exit(1);
    }
}

function uuid(): string
{
    $data = random_bytes(16);
    $data[6] = chr((ord($data[6]) & 0x0F) | 0x40);
    $data[8] = chr((ord($data[8]) & 0x3F) | 0x80);

    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

/** @return list<string> */
function lines(string $path): array
{
    return explode("\n", trim((string) file_get_contents($path)));
}

/** @return list<string> */
function statusTest(string $expr, string $label = 'Expected HTTP status'): array
{
    $labelJson = json_encode($label);

    return [
        "pm.test({$labelJson}, function () {",
        "    {$expr}",
        '});',
    ];
}

/** @return list<string> */
function jsonHas(string $keysCsv): array
{
    $keys = array_map('trim', explode(',', $keysCsv));
    $asserts = ['const json = pm.response.json();'];
    foreach ($keys as $k) {
        if ($k === '') {
            continue;
        }
        // Support dotted paths: data.id
        if (str_contains($k, '.')) {
            $parts = explode('.', $k);
            $expr = 'json';
            foreach ($parts as $p) {
                $expr .= "['{$p}']";
            }
            $asserts[] = "pm.expect({$expr}).to.not.be.undefined;";
        } else {
            $asserts[] = "pm.expect(json).to.have.property('{$k}');";
        }
    }

    return array_merge(
        ['pm.test("Response JSON fields", function () {'],
        $asserts,
        ['});'],
    );
}

/**
 * @param  array<string,string>  $map  jsonPath => envKey
 * @return list<string>
 */
function saveEnvMap(array $map): array
{
    if ($map === []) {
        return [];
    }

    $lines = [
        'if (pm.response.code >= 200 && pm.response.code < 300) {',
        '    const json = pm.response.json();',
    ];
    foreach ($map as $fromJson => $envKey) {
        $parts = explode('.', (string) $fromJson);
        $access = 'json';
        foreach ($parts as $p) {
            $access .= "?.['{$p}']";
        }
        $lines[] = "    if ({$access} !== undefined && {$access} !== null) {";
        $lines[] = "        pm.environment.set('{$envKey}', String({$access}));";
        $lines[] = '    }';
    }
    $lines[] = '}';

    return $lines;
}

/** @param  list<string>  $extra */
function testEvent(array $extra): array
{
    return [[
        'listen' => 'test',
        'script' => [
            'type' => 'text/javascript',
            'exec' => $extra,
        ],
    ]];
}

/**
 * @param  array<string,mixed>  $config
 * @param  array<string,mixed>  $def
 * @return array<string,mixed>
 */
function makeRequestFromDef(array $config, array $def): array
{
    $method = strtoupper((string) ($def['method'] ?? 'GET'));
    $name = (string) ($def['name'] ?? $method);
    $description = (string) ($def['description'] ?? '');
    $body = array_key_exists('body', $def) ? $def['body'] : null;
    $auth = (bool) ($def['auth'] ?? false);
    $status = $def['status'] ?? 200;
    $expectKeys = (string) ($def['expect_keys'] ?? '');
    /** @var array<string,string> $save */
    $save = is_array($def['save'] ?? null) ? $def['save'] : [];
    $skipContract = (bool) ($def['skip_contract'] ?? false);

    $prefix = array_key_exists('api_prefix', $def)
        ? (string) $def['api_prefix']
        : (string) ($config['api_prefix'] ?? '/api/v1');
    $path = (string) ($def['path'] ?? '/');
    $fullPath = rtrim($prefix, '/').'/'.ltrim($path, '/');
    if ($prefix === '' || $prefix === '/') {
        $fullPath = '/'.ltrim($path, '/');
    }

    $pathOnly = $fullPath;
    $query = [];
    if (str_contains($fullPath, '?')) {
        [$pathOnly, $qs] = explode('?', $fullPath, 2);
        parse_str($qs, $query);
    }

    $segments = array_values(array_filter(explode('/', trim($pathOnly, '/')), static fn ($s) => $s !== ''));
    $raw = '{{base_url}}';
    if ($segments !== []) {
        $raw .= '/'.implode('/', $segments);
    }
    if ($query !== []) {
        $raw .= '?'.http_build_query($query);
    }

    $url = [
        'raw' => $raw,
        'host' => ['{{base_url}}'],
        'path' => $segments,
    ];
    if ($query !== []) {
        $url['query'] = [];
        foreach ($query as $k => $v) {
            $url['query'][] = [
                'key' => (string) $k,
                'value' => (string) $v,
            ];
        }
    }

    $headers = [
        ['key' => 'Accept', 'value' => 'application/json'],
    ];
    if ($skipContract) {
        $headers[] = ['key' => 'X-Skip-Contract', 'value' => '1'];
    }

    $authMode = (string) ($config['auth_mode'] ?? 'bearer');
    if ($auth) {
        if ($authMode === 'bearer') {
            $headers[] = ['key' => 'Authorization', 'value' => 'Bearer {{access_token}}'];
        }
        foreach ($config['auth_headers'] ?? [] as $h) {
            if (is_array($h) && isset($h['key'], $h['value'])) {
                $headers[] = ['key' => (string) $h['key'], 'value' => (string) $h['value']];
            }
        }
    }

    $request = [
        'method' => $method,
        'header' => $headers,
        'url' => $url,
        'description' => $description,
        'auth' => ['type' => 'noauth'],
    ];

    if (is_array($body)) {
        $request['body'] = [
            'mode' => 'raw',
            'raw' => json_encode($body, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES),
            'options' => ['raw' => ['language' => 'json']],
        ];
        $headers[] = ['key' => 'Content-Type', 'value' => 'application/json'];
        $request['header'] = $headers;
    }

    $tests = [];
    if (is_int($status) || (is_string($status) && ctype_digit($status))) {
        $code = (int) $status;
        $tests = array_merge($tests, statusTest("pm.response.to.have.status({$code});"));
    } elseif (is_string($status) && $status !== '') {
        $tests = array_merge($tests, statusTest($status));
    }
    if ($expectKeys !== '') {
        $tests = array_merge($tests, jsonHas($expectKeys));
    }
    $tests = array_merge($tests, saveEnvMap($save));

    return [
        'name' => $name,
        'request' => $request,
        'event' => $tests === [] ? [] : testEvent($tests),
        'response' => [],
    ];
}

/**
 * Group requests by folder name (Happy Path / Negative Tests / …).
 *
 * @param  list<array<string,mixed>>  $requests
 * @return list<array<string,mixed>>
 */
function folderize(array $config, array $requests): array
{
    $groups = [];
    foreach ($requests as $def) {
        $folder = (string) ($def['folder'] ?? 'Happy Path');
        $groups[$folder][] = makeRequestFromDef($config, $def);
    }

    $items = [];
    foreach ($groups as $folderName => $reqs) {
        $items[] = [
            'name' => $folderName,
            'item' => $reqs,
        ];
    }

    return $items;
}

/**
 * Index module requests as "Module/name" => def for flow refs.
 *
 * @return array<string,array<string,mixed>>
 */
function indexRequests(array $config): array
{
    $index = [];
    foreach ($config['modules'] ?? [] as $module) {
        $modName = (string) ($module['name'] ?? 'Module');
        foreach ($module['requests'] ?? [] as $def) {
            $reqName = (string) ($def['name'] ?? '');
            if ($reqName !== '') {
                $index[$modName.'/'.$reqName] = $def;
            }
        }
    }
    foreach ($config['setup_requests'] ?? [] as $def) {
        $reqName = (string) ($def['name'] ?? '');
        if ($reqName !== '') {
            $index['Setup/'.$reqName] = $def;
        }
    }

    return $index;
}

/**
 * @param  list<string>  $prerequest
 * @param  list<string>  $test
 * @param  list<array<string,mixed>>  $item
 * @return array<string,mixed>
 */
function buildCollection(
    array $config,
    string $name,
    string $description,
    array $prerequest,
    array $test,
    array $item,
): array {
    $variables = [];
    foreach ($config['collection_variables'] ?? [] as $v) {
        if (! is_array($v) || ! isset($v['key'])) {
            continue;
        }
        $variables[] = [
            'key' => (string) $v['key'],
            'value' => (string) ($v['value'] ?? ''),
        ];
    }

    return [
        'info' => [
            '_postman_id' => uuid(),
            'name' => $name,
            'description' => $description,
            'schema' => 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
        ],
        'variable' => $variables,
        'event' => [
            [
                'listen' => 'prerequest',
                'script' => [
                    'type' => 'text/javascript',
                    'exec' => $prerequest,
                ],
            ],
            [
                'listen' => 'test',
                'script' => [
                    'type' => 'text/javascript',
                    'exec' => $test,
                ],
            ],
        ],
        'item' => $item,
    ];
}

// --- Build main collection -------------------------------------------------

$prerequest = lines($scriptsDir.'/collection-prerequest.js');
$collectionTest = lines($scriptsDir.'/collection-test.js');
$index = indexRequests($config);

$rootItems = [];

// Public
$publicModules = [];
foreach ($config['modules'] ?? [] as $module) {
    if (($module['visibility'] ?? 'protected') !== 'public') {
        continue;
    }
    $publicModules[] = [
        'name' => (string) $module['name'],
        'description' => (string) ($module['description'] ?? ''),
        'item' => folderize($config, $module['requests'] ?? []),
    ];
}
if ($publicModules !== []) {
    $rootItems[] = [
        'name' => 'Public',
        'description' => 'Unauthenticated / public endpoints.',
        'item' => $publicModules,
    ];
}

// Setup
$setupDefs = $config['setup_requests'] ?? [];
if (is_array($setupDefs) && $setupDefs !== []) {
    $rootItems[] = [
        'name' => 'Setup',
        'description' => 'Run once before Protected folders (token mint, fixtures).',
        'item' => array_map(
            static fn (array $def) => makeRequestFromDef($config, $def),
            $setupDefs
        ),
    ];
}

// Protected
$protectedModules = [];
foreach ($config['modules'] ?? [] as $module) {
    if (($module['visibility'] ?? 'protected') !== 'protected') {
        continue;
    }
    $protectedModules[] = [
        'name' => (string) $module['name'],
        'description' => (string) ($module['description'] ?? ''),
        'item' => folderize($config, $module['requests'] ?? []),
    ];
}
if ($protectedModules !== []) {
    $rootItems[] = [
        'name' => 'Protected',
        'description' => 'Authenticated endpoints. Set access_token (or run Setup first).',
        'item' => $protectedModules,
    ];
}

// Flows folder inside main collection (Collection Runner)
$flowFolders = [];
foreach ($config['flows'] ?? [] as $flow) {
    $steps = [];
    foreach ($flow['steps'] ?? [] as $step) {
        if (is_string($step) && str_starts_with($step, 'ref:')) {
            $key = substr($step, 4);
            if (! isset($index[$key])) {
                fwrite(STDERR, "Unknown flow ref: {$key}\n");
                exit(1);
            }
            $steps[] = makeRequestFromDef($config, $index[$key]);
        } elseif (is_array($step)) {
            $steps[] = makeRequestFromDef($config, $step);
        }
    }
    $flowFolders[] = [
        'name' => (string) ($flow['name'] ?? $flow['slug'] ?? 'Flow'),
        'description' => (string) ($flow['description'] ?? ''),
        'item' => $steps,
    ];
}
if ($flowFolders !== []) {
    $rootItems[] = [
        'name' => 'Flows',
        'description' => 'Multi-step sequences. Run one folder in Collection Runner.',
        'item' => $flowFolders,
    ];
}

$collectionName = (string) ($config['collection_name'] ?? 'Laravel API');
$main = buildCollection(
    $config,
    $collectionName,
    "Generated API regression collection.\n\n"
    ."Folders: Public / Setup / Protected / Flows.\n"
    ."Each request documents one action and asserts status (and optional JSON keys).",
    $prerequest,
    $collectionTest,
    $rootItems,
);

$mainPath = $collectionsDir.'/api.json';
file_put_contents($mainPath, json_encode($main, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n");
echo "Wrote {$mainPath}\n";

// --- Standalone flow collections -------------------------------------------

foreach ($config['flows'] ?? [] as $flow) {
    $slug = (string) ($flow['slug'] ?? 'flow');
    $steps = [];
    foreach ($flow['steps'] ?? [] as $step) {
        if (is_string($step) && str_starts_with($step, 'ref:')) {
            $key = substr($step, 4);
            $steps[] = makeRequestFromDef($config, $index[$key]);
        } elseif (is_array($step)) {
            $steps[] = makeRequestFromDef($config, $step);
        }
    }
    $flowColl = buildCollection(
        $config,
        (string) ($flow['name'] ?? $slug),
        (string) ($flow['description'] ?? ''),
        $prerequest,
        $collectionTest,
        $steps,
    );
    $out = $flowsDir.'/'.$slug.'.json';
    file_put_contents($out, json_encode($flowColl, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n");
    echo "Wrote {$out}\n";
}

// --- Environment -----------------------------------------------------------

$envValues = [];
foreach ($config['environment_variables'] ?? [] as $v) {
    if (! is_array($v) || ! isset($v['key'])) {
        continue;
    }
    $type = ($v['type'] ?? 'default') === 'secret' ? 'secret' : 'default';
    $envValues[] = [
        'key' => (string) $v['key'],
        'value' => (string) ($v['value'] ?? ''),
        'type' => $type,
        'enabled' => true,
    ];
}

$env = [
    'id' => uuid(),
    'name' => (string) ($config['environment_name'] ?? 'Local'),
    'values' => $envValues,
    '_postman_variable_scope' => 'environment',
];
$envPath = $envDir.'/local.environment.json';
file_put_contents($envPath, json_encode($env, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n");
echo "Wrote {$envPath}\n";

echo "Done. Import collections + environment into Postman (or sync via Postman MCP / API).\n";
