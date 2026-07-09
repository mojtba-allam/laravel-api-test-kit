<?php

/**
 * verify-timesheet-consistency.php
 *
 * Proves the user time numbers agree across all three layers:
 *
 *   1. DATABASE   — direct query, canonical hours formula.
 *   2. FRONTEND   — the exact JSON the Time Tracking page consumes
 *                   (GET /api/v1/time-logs/summary), hit over real HTTP.
 *   3. EXCEL      — the day-by-day "Daily Timesheet" sheet produced by the
 *                   export button, parsed back out of the generated .xlsx.
 *
 * All three must report the SAME total hours and entry count for the same
 * user + date range, otherwise the script exits non-zero.
 *
 * Usage:
 *   php tests/api/verify-timesheet-consistency.php
 *   BASE_URL="http://127.0.0.1:8000" php tests/api/verify-timesheet-consistency.php
 *   USER_ID="..." START=2026-05-01 END=2026-05-31 php tests/api/verify-timesheet-consistency.php
 */

require __DIR__.'/../../vendor/autoload.php';

$app = require_once __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

use Carbon\Carbon;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;
use Modules\Analytics\Services\AnalyticsExportService;
use Modules\TimeLog\Models\TimeLog;
use Modules\TimeLog\Services\TimeLogService;
use Modules\User\Models\User;
use PhpOffice\PhpSpreadsheet\IOFactory;

// ─── Tiny output helpers ───────────────────────────────────────────────────────
const GREEN = "\033[0;32m";
const RED = "\033[0;31m";
const YELLOW = "\033[1;33m";
const NC = "\033[0m";

$failures = 0;

function ok(string $msg): void
{
    echo GREEN.'✓ '.NC.$msg."\n";
}
function bad(string $msg): void
{
    global $failures;
    $failures++;
    echo RED.'✗ '.NC.$msg."\n";
}
function approxEqual(float $a, float $b, float $eps = 0.01): bool
{
    return abs($a - $b) <= $eps;
}

$baseUrl = rtrim(getenv('BASE_URL') ?: 'http://127.0.0.1:8000', '/');

// ─── Pick a user + range ────────────────────────────────────────────────────────

$userId = getenv('USER_ID') ?: TimeLog::withoutGlobalScopes()
    ->selectRaw('user_id, COUNT(*) c')
    ->whereNotNull('user_id')
    ->groupBy('user_id')
    ->orderByDesc('c')
    ->value('user_id');

$user = $userId ? User::find($userId) : null;
if (! $user) {
    fwrite(STDERR, RED."No user with time logs found.\n".NC);
    exit(1);
}

// Bound the range to the user's real activity unless overridden.
$minLogged = TimeLog::withoutGlobalScopes()->where('user_id', $user->id)->min('logged_date');
$maxLogged = TimeLog::withoutGlobalScopes()->where('user_id', $user->id)->max('logged_date');
$start = getenv('START') ?: $minLogged;
$end = getenv('END') ?: $maxLogged;
$start = $start ? Carbon::parse($start)->toDateString() : now()->subYear()->toDateString();
$end = $end ? Carbon::parse($end)->toDateString() : now()->toDateString();

echo "==============================================\n";
echo " Timesheet consistency check\n";
echo " User    : {$user->name} ({$user->id})\n";
echo " Range   : {$start} → {$end}\n";
echo " Base URL: {$baseUrl}\n";
echo "==============================================\n\n";

// ─── 1. DATABASE (canonical) ──────────────────────────────────────────────────

/** @var TimeLogService $timeLogService */
$timeLogService = app(TimeLogService::class);

$dbLogs = TimeLog::withoutGlobalScopes()
    ->where('user_id', $user->id)
    ->whereBetween(DB::raw('DATE(COALESCE(logged_date, start_time))'), [$start, $end])
    ->get();

$dbMinutes = $dbLogs->sum(fn ($l) => $timeLogService->logHours($l) * 60);
$dbHours = round($dbMinutes / 60, 2);
$dbEntries = $dbLogs->count();
$dbBillable = round($dbLogs->where('is_billable', true)->sum(fn ($l) => $timeLogService->logHours($l)), 2);

echo "1. DATABASE\n";
echo "   total_hours = {$dbHours}\n";
echo "   entries     = {$dbEntries}\n";
echo "   billable_hrs= {$dbBillable}\n\n";

// ─── 2. FRONTEND API (what the page renders) ──────────────────────────────────

// Mint a short-lived token for this user so we call the real HTTP endpoint.
$token = $user->createToken('timesheet-verify')->plainTextToken;

$summaryUrl = $baseUrl.'/api/v1/time-logs/summary?'.http_build_query([
    'user_id' => $user->id,
    'start_date' => $start,
    'end_date' => $end,
]);

$ch = curl_init($summaryUrl);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => [
        'Authorization: Bearer '.$token,
        'Accept: application/json',
    ],
    CURLOPT_TIMEOUT => 30,
]);
$apiRaw = curl_exec($ch);
$apiCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$apiHours = null;
$apiEntries = null;
$apiBillable = null;
if ($apiCode === 200) {
    $decoded = json_decode($apiRaw, true);
    $payload = $decoded['data'] ?? $decoded;
    $apiHours = isset($payload['total_hours']) ? (float) $payload['total_hours'] : null;
    $apiEntries = isset($payload['total_logs']) ? (int) $payload['total_logs'] : null;
    $apiBillable = isset($payload['billable_hours']) ? (float) $payload['billable_hours'] : null;
}

echo "2. FRONTEND API  (GET /api/v1/time-logs/summary)  HTTP {$apiCode}\n";
echo '   total_hours = '.($apiHours ?? 'n/a')."\n";
echo '   entries     = '.($apiEntries ?? 'n/a')."\n";
echo '   billable_hrs= '.($apiBillable ?? 'n/a')."\n\n";

// Clean up the throwaway token.
$user->tokens()->where('name', 'timesheet-verify')->delete();

// ─── 3. EXCEL (the export button output) ──────────────────────────────────────

/** @var AnalyticsExportService $exportService */
$exportService = app(AnalyticsExportService::class);

$bytes = $exportService->build([
    'scope' => 'user',
    'user_id' => $user->id,
    'start_date' => $start,
    'end_date' => $end,
    'sheets' => ['daily_activity', 'summary', 'tasks', 'time_logs'],
    'limit' => 50000,
]);

$tmp = tempnam(sys_get_temp_dir(), 'timesheet').'.xlsx';
file_put_contents($tmp, $bytes);
$spreadsheet = IOFactory::load($tmp);
$sheet = $spreadsheet->getSheetByName('Daily Activity');

$xlHours = null;
$xlEntries = 0;
if ($sheet) {
    $rows = $sheet->toArray();
    // Header is row 0; the last row is the bold TOTAL row.
    $header = array_map('strval', $rows[0]);
    $hoursCol = array_search('Hours', $header, true);
    $entriesCol = array_search('Entries', $header, true);
    $dateCol = 0;

    foreach (array_slice($rows, 1) as $r) {
        if (($r[$dateCol] ?? '') === 'TOTAL') {
            $xlHours = $hoursCol !== false ? (float) $r[$hoursCol] : null;

            continue;
        }
        if ($entriesCol !== false) {
            $xlEntries += (int) ($r[$entriesCol] ?? 0);
        }
    }
}
@unlink($tmp);

echo "3. EXCEL  (Daily Timesheet sheet, TOTAL row)\n";
echo '   total_hours = '.($xlHours ?? 'n/a')."\n";
echo '   entries     = '.$xlEntries."\n\n";

// ─── Compare ──────────────────────────────────────────────────────────────────

echo "----------------------------------------------\n";
echo "Comparisons\n";
echo "----------------------------------------------\n";

// DB vs API
if ($apiHours === null) {
    bad('FRONTEND API summary unavailable (HTTP '.$apiCode.') — is the server running?');
} elseif (approxEqual($dbHours, $apiHours)) {
    ok("DB total_hours ({$dbHours}) == API total_hours ({$apiHours})");
} else {
    bad("DB total_hours ({$dbHours}) != API total_hours ({$apiHours})");
}

if ($apiEntries !== null) {
    if ($apiEntries === $dbEntries) {
        ok("DB entries ({$dbEntries}) == API entries ({$apiEntries})");
    } else {
        bad("DB entries ({$dbEntries}) != API entries ({$apiEntries})");
    }
}

if ($apiBillable !== null) {
    if (approxEqual($dbBillable, $apiBillable)) {
        ok("DB billable_hours ({$dbBillable}) == API billable_hours ({$apiBillable})");
    } else {
        bad("DB billable_hours ({$dbBillable}) != API billable_hours ({$apiBillable})");
    }
}

// DB vs Excel
if ($xlHours === null) {
    bad('EXCEL Daily Timesheet TOTAL row not found.');
} elseif (approxEqual($dbHours, $xlHours, 0.05)) {
    ok("DB total_hours ({$dbHours}) == Excel total_hours ({$xlHours})");
} else {
    bad("DB total_hours ({$dbHours}) != Excel total_hours ({$xlHours})");
}

if ($xlEntries === $dbEntries) {
    ok("DB entries ({$dbEntries}) == Excel entries ({$xlEntries})");
} else {
    bad("DB entries ({$dbEntries}) != Excel entries ({$xlEntries})");
}

echo "\n==============================================\n";
if ($failures === 0) {
    echo GREEN."All layers agree — DB == Frontend == Excel\n".NC;
    exit(0);
}
echo RED."{$failures} mismatch(es) found.\n".NC;
exit(1);
