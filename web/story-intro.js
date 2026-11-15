// SceneRenderer owns layout and visibility; FlowDriver owns page/scene navigation.
export const STORY_INTRO_SCENES = Object.freeze(['StoryIntro01', 'StoryIntro02']);
export const STORY_INTRO_SCENE_UUIDS = Object.freeze([
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb401',
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb402',
]);
export const STORY_INTRO_STORAGE_SUFFIX = 'story_cat_liquid_seen_v1';

export function attachStoryIntro(flow, { story, storageKey, isReady, saveGame, replay = false }) {
  if (story.textMode !== 'bottom-typewriter' || story.pages.length !== 2
    || story.pages.some((page, i) => page.sceneUuid !== STORY_INTRO_SCENE_UUIDS[i] || page.panels.length !== 4)) {
    throw new Error('[Story intro] 가로 4컷 이야기 데이터가 올바르지 않습니다.');
  }
  const segmenter = new Intl.Segmenter('ko', { granularity: 'grapheme' });
  let state = null;
  let frame = 0;
  let unsubscribeAdvance = null;

  const stop = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    unsubscribeAdvance?.();
    unsubscribeAdvance = null;
    state = null;
  };
  const complete = () => {
    stop();
    localStorage.setItem(storageKey, '1');
    void saveGame();
    return true;
  };
  const finishLine = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    state.typing = false;
    state.ready = state.index === 3;
    state.renderer.update({ story: {
      dialogue: state.characters.join(''),
      hint: state.ready ? 'next를 눌러 계속' : '터치해서 다음 장면',
      nextReady: state.ready,
    } });
  };
  const tick = (now) => {
    if (!state || !state.renderer.getElement(state.dialogueId)?.isConnected) {
      stop();
      return;
    }
    if (state.index < 0) {
      if (now >= state.startAt) showPanel(0, now);
      else frame = requestAnimationFrame(tick);
      return;
    }
    const count = Math.min(state.characters.length,
      Math.max(0, Math.floor((now - state.startAt) / story.motion.typewriterMsPerCharacter)));
    if (count !== state.shown) {
      state.shown = count;
      state.renderer.update({ story: { dialogue: state.characters.slice(0, count).join('') } });
    }
    if (count === state.characters.length) finishLine();
    else frame = requestAnimationFrame(tick);
  };
  const showPanel = (index, now) => {
    const panel = story.pages[state.pageIndex].panels[index];
    const card = state.renderer.getElement(`story-card-${String(panel.number).padStart(2, '0')}`);
    if (!card) throw new Error(`[Story intro] 컷이 없습니다: ${panel.number}`);
    state.index = index;
    state.characters = [...segmenter.segment(panel.caption)].map(item => item.segment);
    state.shown = 0;
    state.typing = true;
    state.ready = false;
    state.startAt = now + story.motion.entryDurationMs;
    card.classList.add('story-panel-enter');
    state.renderer.update({ story: {
      [`panel${String(panel.number).padStart(2, '0')}`]: true,
      dialogue: '', hint: '터치하면 대사가 모두 표시됩니다', nextReady: false,
    } });
    state.renderer.getElement(state.dialogueId).setAttribute('aria-label', panel.caption);
    frame = requestAnimationFrame(tick);
  };
  const advance = () => {
    if (!state || state.index < 0) return;
    if (state.typing) finishLine();
    else if (!state.ready) showPanel(state.index + 1, performance.now());
  };

  flow.defineCondition('story.firstEntry', () =>
    isReady() && (replay || localStorage.getItem(storageKey) !== '1'));
  flow.defineCondition('story.pageComplete', () => state?.pageIndex === 0 && state.ready);
  flow.defineCondition('story.finish', () => state?.pageIndex === 1 && state.ready ? complete() : false);
  flow.defineCondition('story.complete', complete);
  // Seed visibility before show(): no flash of unread panels or next on first entry.
  const hiddenPanels = Object.fromEntries(story.pages.flatMap(page => page.panels)
    .map(panel => [`panel${String(panel.number).padStart(2, '0')}`, false]));
  flow.update({ story: { ...hiddenPanels, dialogue: '', hint: '', nextReady: false } });
  flow.on('scene:enter', ({ sceneUuid, renderer, popup }) => {
    if (popup) return;
    stop();
    const pageIndex = STORY_INTRO_SCENE_UUIDS.indexOf(sceneUuid);
    if (pageIndex < 0) return;
    const pageNumber = String(pageIndex + 1).padStart(2, '0');
    const dialogueId = `story-dialogue-${pageNumber}`;
    renderer.update({ story: { ...hiddenPanels, dialogue: '', hint: '', nextReady: false } });
    state = { pageIndex, renderer, dialogueId, index: -1, typing: false, ready: false,
      startAt: performance.now() + story.motion.initialDelayMs };
    unsubscribeAdvance = renderer.on(`story-advance-${pageNumber}:click`, advance);
    for (const action of ['next', 'skip', 'dialogue']) {
      const stableId = `story-${action}-${pageNumber}`;
      const button = renderer.getElement(stableId);
      if (!button) throw new Error(`[Story intro] 버튼이 없습니다: ${stableId}`);
      button.setAttribute('role', 'button');
      button.setAttribute('tabindex', '0');
      button.setAttribute('aria-label', action === 'skip' ? '이야기 건너뛰기'
        : action === 'dialogue' ? '이야기 계속' : pageIndex === 0 ? '다음 이야기' : '모험 시작');
      button.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        button.click();
      });
    }
    renderer.getElement(`story-advance-${pageNumber}`).setAttribute('aria-hidden', 'true');
    frame = requestAnimationFrame(tick);
  });
}
