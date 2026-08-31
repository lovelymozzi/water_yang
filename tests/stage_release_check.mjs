import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

const shell = readFileSync(new URL('../godot-shell.html', import.meta.url), 'utf8');
const mainScene = readFileSync(new URL('../scripts/main_scene.gd', import.meta.url), 'utf8');
const stages = readdirSync(new URL('../resources/levels/', import.meta.url))
  .filter(name => /^stage_\d{3}\.json$/.test(name))
  .sort();

assert.equal(stages.length, 187);
assert.deepEqual(stages, Array.from({ length: 187 }, (_, index) => `stage_${String(index + 1).padStart(3, '0')}.json`));
assert.doesNotMatch(shell, /localStorage\.setItem\([^\n]*progress_v1/);
assert.match(shell, /new ProgressManager\(\{ storagePrefix: STORAGE_PREFIX, maxStage: 187 \}\)/);
assert.match(shell, /currentMapStage = \(await progress\.recordClear/);
assert.match(shell, /const savedGame = await loadGame\(\);\s+restoreGameState\(savedGame\);/);
assert.match(shell, /window\.HubGame\?\.save\) await window\.HubGame\.save\(HUB_SAVE_KEY, snapshot\)/);
assert.match(shell, /window\.HubGame\?\.submitScore\) await window\.HubGame\.submitScore\(HUB_LEADERBOARD_KEY, value\)/);
assert.match(shell, /window\.HubGame\?\.getLeaderboard\) \{\s+const remote = await window\.HubGame\.getLeaderboard\(HUB_LEADERBOARD_KEY, 10\)/);
assert.match(shell, /await submitStageLeaderboard\(currentMapStage\);/);
assert.match(mainScene, /if not UiBridge\.is_hosted:\s+_setup_stage_label\(\)\s+_setup_replay_button\(\)/);
