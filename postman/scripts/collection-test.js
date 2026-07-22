/**
 * Collection-level contract tests for Laravel JSON APIs.
 *
 * Skips when the request sets header: X-Skip-Contract: 1
 * (use for HTML health pages, file downloads, empty 204s, etc.)
 *
 * Expected error envelope (adjust in docs/POSTMAN_JSON_CONTRACT.md if your
 * API differs, then edit this script to match):
 *   { "error": "...", "message": "...", "errors"?: { field: [...] } }
 */
const skip = pm.request.headers.has('X-Skip-Contract');
if (skip) {
    return;
}

const code = pm.response.code;
const ct = pm.response.headers.get('Content-Type') || '';
const text = pm.response.text();

pm.test('Response is JSON when body present', function () {
    if (code === 204 || text.length === 0) {
        return;
    }
    pm.expect(ct).to.match(/json/i);
    pm.response.json();
});

if (code >= 400 && text.length > 0) {
    const json = pm.response.json();
    pm.test('Error envelope has message (and error or errors)', function () {
        pm.expect(json).to.have.property('message');
        const hasError = Object.prototype.hasOwnProperty.call(json, 'error');
        const hasErrors = Object.prototype.hasOwnProperty.call(json, 'errors');
        pm.expect(hasError || hasErrors).to.eql(true);
    });
}
