// Execute the exact inline workflow script with fixture GitHub API responses.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const workflow = fs.readFileSync(path.join(__dirname, '../.github/workflows/release-guard.yml'), 'utf8');
const section = workflow.split('  validate-release-push:')[1].split('  validate-main-push:')[0];
const script = section.split('          script: |')[1].split('\n')
  .filter(line => line.startsWith('            ')).map(line => line.slice(12)).join('\n');
assert(script.includes('listPullRequestsAssociatedWithCommit'));
const execute = new (Object.getPrototypeOf(async function(){}).constructor)('github', 'context', 'core', script);
async function check(name, changes = {}, shouldPass = false) {
  const shas = changes.shas || ['new'];
  const pr = {number: 9, merged: true, state: 'closed', merged_at: '2026-10-08T00:00:00Z',
    base: {ref: 'release', repo: {full_name: 'Gutiz/win-c-cleaner'}},
    merge_commit_sha: shas.at(-1), commits: shas.length, ...changes.pr};
  const context = {eventName: 'push', sha: shas.at(-1), repo: {owner: 'Gutiz', repo: 'win-c-cleaner'},
    payload: {before: 'old', after: shas.at(-1), ref: 'refs/heads/release', forced: false,
      created: false, deleted: false, ...changes.payload}};
  const github = {rest: {repos: {
    compareCommitsWithBasehead: async ({page}) => ({data: {status: 'ahead', behind_by: 0,
      total_commits: shas.length, commits: shas.slice((page - 1) * 100, page * 100).map(sha => ({sha})),
      ...changes.compare}}), listPullRequestsAssociatedWithCommit: () => {}
  }, pulls: {get: async () => ({data: pr})}}, paginate: async (_, {commit_sha}) => {
    if (changes.apiFailure) throw new Error('API unavailable');
    return changes.associations ? changes.associations(commit_sha) : [{number: 9}];
  }};
  let passed = true;
  try { await execute(github, context, {info() {}}); } catch { passed = false; }
  assert.equal(passed, shouldPass, name);
  console.log(`PASS ${name}`);
}
(async () => {
  await check('squash of multi-commit PR', {pr: {commits: 4}}, true);
  await check('rebase of three commits', {shas: ['a','b','c']}, true);
  await check('paginated rebase range', {shas: Array.from({length: 205}, (_, i) => `sha-${i}`)}, true);
  await check('direct push without PR', {associations: () => []});
  await check('open PR', {pr: {merged: false, state: 'open', merged_at: null}});
  await check('closed unmerged PR', {pr: {merged: false, merged_at: null}});
  await check('PR targeting main', {pr: {base: {ref: 'main', repo: {full_name: 'Gutiz/win-c-cleaner'}}}});
  await check('PR for another repository', {pr: {base: {ref: 'release', repo: {full_name: 'other/repo'}}}});
  await check('associated old PR with different merge tip', {pr: {merge_commit_sha: 'older'}});
  await check('unrelated earlier direct push', {shas: ['direct','tip'], associations: sha => sha === 'tip' ? [{number: 9}] : []});
  await check('earlier commit from another PR', {shas: ['other','tip'], associations: sha => [{number: sha === 'tip' ? 9 : 8}]});
  await check('unexpected range length', {shas: ['a','b'], pr: {commits: 3}});
  await check('force push', {payload: {forced: true}});
  await check('branch creation', {payload: {created: true}});
  await check('branch deletion', {payload: {deleted: true}});
  await check('zero before', {payload: {before: '00000000'}});
  await check('wrong branch', {payload: {ref: 'refs/heads/main'}});
  await check('divergent history', {compare: {status: 'diverged', behind_by: 1}});
  await check('incomplete comparison', {compare: {commits: [], total_commits: 1}});
  await check('API failure', {apiFailure: true});
})().catch(error => { console.error(error); process.exitCode = 1; });
