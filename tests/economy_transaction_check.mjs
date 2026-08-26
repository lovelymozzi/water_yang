import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const shell = readFileSync(new URL('../godot-shell.html', import.meta.url), 'utf8');
const helper = shell.match(/let economyTransactionTail = Promise\.resolve\(\);.*?\n};/s)?.[0];
assert.ok(helper, 'godot-shell.html must define runEconomyTransaction');
const runEconomyTransaction = Function(`${helper}\nreturn runEconomyTransaction;`)();

let running = 0;
let peak = 0;
let runs = 0;
const work = async () => {
  runs += 1;
  peak = Math.max(peak, ++running);
  await new Promise(resolve => setTimeout(resolve, 5));
  running -= 1;
};
const first = runEconomyTransaction('purchase', work);
assert.equal(first, runEconomyTransaction('purchase', work), 'same action must share its in-flight transaction');
await Promise.all([first, runEconomyTransaction('reward', work)]);
assert.equal(runs, 2, 'duplicate action must not run twice');
assert.equal(peak, 1, 'currency transactions must not overlap');
