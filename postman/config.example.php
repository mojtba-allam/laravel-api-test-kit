<?php

/**
 * Project Postman generator config.
 *
 * Copy to config.php and edit for your Laravel API:
 *   cp postman/config.example.php postman/config.php
 *
 * Then: php postman/generate-collections.php
 */

declare(strict_types=1);

return [
    // Display names (no product branding required)
    'collection_name' => 'Laravel API',
    'environment_name' => 'Local',

    // Default base URL used in the generated environment
    'base_url' => 'http://127.0.0.1:8000',

    // Prefix applied to every request path (no trailing slash)
    'api_prefix' => '/api/v1',

    // Environment variables written into environments/local.environment.json
    'environment_variables' => [
        ['key' => 'base_url', 'value' => 'http://127.0.0.1:8000', 'type' => 'default'],
        ['key' => 'access_token', 'value' => '', 'type' => 'secret'],
        ['key' => 'resource_id', 'value' => '', 'type' => 'default'],
        ['key' => 'unique_suffix', 'value' => '', 'type' => 'default'],
    ],

    // Collection variables (optional defaults when env is missing)
    'collection_variables' => [
        ['key' => 'base_url', 'value' => 'http://127.0.0.1:8000'],
    ],

    /**
     * Auth mode for protected requests:
     * - bearer  → Authorization: Bearer {{access_token}}
     * - none    → no auth headers
     * - custom  → use auth_headers below only
     */
    'auth_mode' => 'bearer',

    // Extra headers always added when auth_mode is bearer/custom on protected requests
    'auth_headers' => [],

    /**
     * Modules become nested folders under Public / Protected.
     * Each request:
     *   name, method, path (relative to api_prefix), description,
     *   body (array|null), auth (bool), status (int|string expr),
     *   expect_keys (csv string), save (map jsonPath => envKey),
     *   folder (Happy Path|Negative Tests), skip_contract (bool)
     */
    'modules' => [
        [
            'name' => 'Health',
            'visibility' => 'public', // public | protected
            'requests' => [
                [
                    'name' => 'GET health',
                    'method' => 'GET',
                    'path' => '/up',
                    'description' => "Health check.\n\n**Expect:** 200.",
                    'body' => null,
                    'auth' => false,
                    'status' => 200,
                    'folder' => 'Happy Path',
                    // /up often returns HTML — skip JSON contract
                    'skip_contract' => true,
                    'api_prefix' => '', // absolute from host root
                ],
            ],
        ],
        [
            'name' => 'Resources',
            'visibility' => 'protected',
            'requests' => [
                [
                    'name' => 'POST resources',
                    'method' => 'POST',
                    'path' => '/resources',
                    'description' => "Create a resource.\n\n**Expect:** 201 + `id`.",
                    'body' => [
                        'name' => 'Resource-{{unique_suffix}}',
                        'description' => 'Created by Postman generator',
                    ],
                    'auth' => true,
                    'status' => 201,
                    'expect_keys' => 'id,name',
                    'save' => ['id' => 'resource_id'],
                    'folder' => 'Happy Path',
                ],
                [
                    'name' => 'GET resources/{id}',
                    'method' => 'GET',
                    'path' => '/resources/{{resource_id}}',
                    'description' => "Fetch one resource.\n\n**Expect:** 200.",
                    'body' => null,
                    'auth' => true,
                    'status' => 200,
                    'expect_keys' => 'id,name',
                    'folder' => 'Happy Path',
                ],
                [
                    'name' => 'POST resources [missing name]',
                    'method' => 'POST',
                    'path' => '/resources',
                    'description' => "Validation failure.\n\n**Expect:** 422 with error envelope.",
                    'body' => [
                        'description' => 'missing required name',
                    ],
                    'auth' => true,
                    'status' => 422,
                    'folder' => 'Negative Tests',
                ],
                [
                    'name' => 'GET resources/{id} [unauthenticated]',
                    'method' => 'GET',
                    'path' => '/resources/{{resource_id}}',
                    'description' => "Auth boundary.\n\n**Expect:** 401.",
                    'body' => null,
                    'auth' => false,
                    'status' => 401,
                    'folder' => 'Negative Tests',
                ],
            ],
        ],
    ],

    /**
     * Setup folder (run before protected suites). Example: mint token via a local helper.
     * Leave empty if you paste tokens into the environment manually.
     */
    'setup_requests' => [
        // Example (disabled by default — enable when you have a mint endpoint):
        // [
        //     'name' => 'Mint access token',
        //     'method' => 'POST',
        //     'path' => '/auth/token',
        //     'description' => "Mint a Sanctum token for Postman runs.",
        //     'body' => ['email' => 'qa@example.test', 'password' => 'secret'],
        //     'auth' => false,
        //     'status' => 200,
        //     'expect_keys' => 'token',
        //     'save' => ['token' => 'access_token'],
        //     'api_prefix' => '/api/v1',
        // ],
    ],

    /**
     * Multi-step flow collections (one runnable sequence each).
     * `steps` reference request definitions the same shape as module requests,
     * or `ref` strings like "Resources/POST resources".
     */
    'flows' => [
        [
            'slug' => 'flow-resource-crud',
            'name' => 'Flow — Resource create then fetch',
            'description' => "Happy-path CRUD chain.\n\nRun with Collection Runner + Local environment.",
            'steps' => [
                'ref:Resources/POST resources',
                'ref:Resources/GET resources/{id}',
            ],
        ],
    ],
];
