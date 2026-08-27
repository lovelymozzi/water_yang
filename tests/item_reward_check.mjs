import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const shell = readFileSync(new URL('../godot-shell.html', import.meta.url), 'utf8');
const literal = source => Function(`return (${source});`)();

const startCount = Number(shell.match(/const ITEM_START_COUNT = (\d+);/)?.[1]);
const itemKeys = literal(shell.match(/const ITEM_KEYS = (\[[^\n]+]);/)?.[1]);
const rewardTable = literal(shell.match(/const CLEAR_ITEM_REWARD_TABLE = (\[[\s\S]*?\n\]);/)?.[1]);
const rewardUi = literal(shell.match(/const ITEM_REWARD_UI = (\{[\s\S]*?\n\});\nconst LOBBY_REWARD_TRAIL_COUNT/)?.[1]);
const coinLayerOffsets = literal(shell.match(/const LEVEL_WIN_COIN_REWARD_LAYER_OFFSETS = (\{[\s\S]*?\n\});/)?.[1]);
const coinRewardPos = literal(shell.match(/const LEVEL_WIN_COIN_REWARD_POS = (\{[\s\S]*?\n\});/)?.[1]);
const normalizeSource = shell.match(/function normalizeItemCounts\(saved = \{\}\) \{[\s\S]*?\n\}/)?.[0];
const normalizeItemCounts = Function('ITEM_KEYS', 'ITEM_START_COUNT', `${normalizeSource}\nreturn normalizeItemCounts;`)(itemKeys, startCount);
const levelWinRewardSource = shell.slice(
  shell.indexOf('function setRewardLayers'),
  shell.indexOf('function clearLobbyItemRewardLayers')
);
const queueRewardSource = shell.match(/function queueLobbyItemReward\(reward\) \{[\s\S]*?\n\}/)?.[0];
const playQueuedSource = shell.slice(
  shell.indexOf('function playQueuedLobbyItemRewards'),
  shell.indexOf('function requestItem')
);
const syncLevelWinItemReward = Function(
  'ITEM_REWARD_UI',
  'LEVEL_WIN_COIN_REWARD_POS',
  'LEVEL_WIN_COIN_REWARD_LAYER_OFFSETS',
  `${levelWinRewardSource}\nreturn syncLevelWinItemReward;`
)(rewardUi, coinRewardPos, coinLayerOffsets);
const makeQueueLobbyItemReward = Function(
  'ITEM_REWARD_UI',
  `let pendingLobbyItemRewards = [];\nlet saved = null;\nfunction savePendingLobbyItemRewards() { saved = [...pendingLobbyItemRewards]; }\n${queueRewardSource}\nreturn { queueLobbyItemReward, pendingLobbyItemRewards, get saved() { return saved; } };`
);

function makeLevelWinRenderer() {
  const groups = {
    coin: { style: {} },
    remove: { style: {} },
    timestop: { style: {} },
    move: { style: {} },
  };
  const elements = {};
  for (const stableId of Object.keys(coinLayerOffsets)) {
    elements[stableId] = {
      style: {},
      closest: selector => selector === '[data-group="coin_reward"]' ? groups.coin : null,
    };
  }
  for (const [item, cfg] of Object.entries(rewardUi)) {
    for (const stableId of cfg.levelWinLayers) {
      elements[stableId] = { style: {}, closest: () => groups[item] };
    }
  }
  return { groups, elements, getElement: stableId => elements[stableId] || null };
}

function levelWinState(reward) {
  const renderer = makeLevelWinRenderer();
  syncLevelWinItemReward(renderer, reward);
  return {
    groups: Object.fromEntries(Object.entries(renderer.groups).map(([key, group]) => [
      key,
      { left: group.style.left, top: group.style.top },
    ])),
    elements: Object.fromEntries(Object.entries(renderer.elements).map(([key, el]) => [
      key,
      { left: el.style.left, top: el.style.top, display: el.style.display },
    ])),
  };
}

assert.equal(startCount, 3);
assert.deepEqual(itemKeys, ['remove', 'timestop', 'move']);
assert.equal(rewardTable.reduce((sum, entry) => sum + entry.weight, 0), 100);
assert.equal(rewardTable.find(entry => entry.item == null)?.weight, 75);
assert.deepEqual(rewardTable.filter(entry => entry.item).map(entry => entry.item).sort(), [...itemKeys].sort());
assert.deepEqual(coinRewardPos, {
  solo: { x: 160, y: 305, contentOffsetX: -67 },
  item: { x: 156, y: 305 },
});

for (const item of itemKeys) {
  assert.ok(rewardUi[item], `${item} reward UI config missing`);
  assert.ok(rewardUi[item].levelWinLayers.length >= 4, `${item} LevelWin layers missing`);
  assert.ok(rewardUi[item].levelWinPos, `${item} LevelWin group position missing`);
  assert.ok(rewardUi[item].levelWinLayerOffsets, `${item} LevelWin layer offsets missing`);
  assert.ok(rewardUi[item].lobbyLayers.includes(rewardUi[item].lobbyIcon), `${item} lobby icon must be animated`);
}

assert.deepEqual(normalizeItemCounts({ remove: '7', timestop: -2, move: 'bad' }), {
  remove: 7,
  timestop: 0,
  move: 3,
});
{
  const queue = makeQueueLobbyItemReward(rewardUi);
  queue.queueLobbyItemReward({ item: 'remove', count: 1 });
  queue.queueLobbyItemReward({ item: 'remove', count: 1 });
  queue.queueLobbyItemReward({ item: 'timestop', count: 1 });
  queue.queueLobbyItemReward({ item: 'move', count: 1 });
  queue.queueLobbyItemReward({ item: 'unknown', count: 1 });
  assert.deepEqual(queue.pendingLobbyItemRewards, [
    { item: 'remove', count: 1 },
    { item: 'timestop', count: 1 },
    { item: 'move', count: 1 },
  ]);
  assert.deepEqual(queue.saved, queue.pendingLobbyItemRewards);
}
assert.match(shell, /const LOBBY_ITEM_REWARD_STORAGE_KEY = STORAGE_PREFIX \+ 'lobby_item_rewards_v1';/);
assert.match(shell, /let pendingLobbyItemRewards = readPendingLobbyItemRewards\(\);/);
assert.match(playQueuedSource, /requestAnimationFrame/);
assert.match(playQueuedSource, /pendingLobbyItemRewards\.length/);
assert.match(playQueuedSource, /readPendingLobbyItemRewards/);
assert.match(playQueuedSource, /savePendingLobbyItemRewards/);
assert.ok(
  playQueuedSource.indexOf('pendingLobbyItemRewards.splice(0)') > playQueuedSource.indexOf('if (hidden)'),
  'Lobby reward queue must be consumed only after the Lobby renderer is visible'
);
assert.deepEqual(levelWinState(null).groups, {
  coin: { left: '160px', top: '305px' },
  remove: { left: '36px', top: '307px' },
  timestop: { left: '42px', top: '303px' },
  move: { left: '43px', top: '302px' },
});
assert.deepEqual(levelWinState({}).groups.coin, { left: '160px', top: '305px' });
assert.deepEqual(levelWinState({ item: 'unknown', count: 1 }).groups.coin, { left: '160px', top: '305px' });
assert.deepEqual(levelWinState(null).elements['gold-glow-12'], { left: '-67px', top: '0px', display: undefined });
assert.deepEqual(levelWinState(null).elements['plain-text-9'], { left: '28px', top: '82px', display: undefined });
assert.deepEqual(levelWinState({ item: 'remove', count: 1 }).groups.coin, { left: '156px', top: '305px' });
assert.deepEqual(levelWinState({ item: 'remove', count: 1 }).elements['gold-glow-12'], { left: '0px', top: '0px', display: undefined });
assert.deepEqual(levelWinState({ item: 'remove', count: 1 }).groups.remove, { left: '36px', top: '307px' });
assert.deepEqual(levelWinState({ item: 'timestop', count: 1 }).groups.timestop, { left: '42px', top: '303px' });
assert.deepEqual(levelWinState({ item: 'move', count: 1 }).groups.move, { left: '43px', top: '302px' });
assert.deepEqual(levelWinState({ item: 'remove', count: 1 }).elements['item1-png-2511'], {
  left: '52px',
  top: '51px',
  display: '',
});
assert.deepEqual(levelWinState({ item: 'remove', count: 1 }).elements['item2-png-2512'], {
  left: '49px',
  top: '49px',
  display: 'none',
});
