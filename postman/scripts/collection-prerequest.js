/**
 * Collection-level prerequest — runs before every request.
 * Keep this generic; put project-specific logic in postman/config.php bodies
 * or per-request scripts after you customize the generator.
 */
const baseUrl = pm.environment.get('base_url') || pm.collectionVariables.get('base_url');
if (!baseUrl) {
    console.warn('base_url is not set — select a Postman environment before running.');
}

// Stable unique suffix for one Collection Runner / folder run.
if (!pm.environment.get('unique_suffix')) {
    pm.environment.set('unique_suffix', String(Date.now()).slice(-8) + String(Math.floor(Math.random() * 90 + 10)));
}
