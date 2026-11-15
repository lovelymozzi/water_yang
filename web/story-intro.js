// SceneRenderer owns layout and visibility; FlowDriver owns page/scene navigation.
export const STORY_INTRO_SCENES = Object.freeze(['StoryIntro01', 'StoryIntro02']);
export const STORY_INTRO_SCENE_UUIDS = Object.freeze([
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb401',
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb402',
]);
export const STORY_INTRO_STORAGE_SUFFIX = 'story_cat_liquid_seen_v1';

export function attachStoryIntro(flow, { story, storageKey, isReady, saveGame, replay = false }) {
  if (story.textMode !== 'none' || story.pages.length !== 2
    || story.pages.some((page, i) => page.sceneUuid !== STORY_INTRO_SCENE_UUIDS[i] || page.panels.length !== 4)) {
    throw new Error('[Story intro] 가로 4컷 이야기 데이터가 올바르지 않습니다.');
  }
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
  const tick = (now) => {
    if (!state || !state.renderer.getElement(state.firstCardId)?.isConnected) {
      stop();
      return;
    }
    if (now >= state.startAt) {
      frame = 0;
      showPanel(0);
    } else frame = requestAnimationFrame(tick);
  };
  const showPanel = (index) => {
    const panel = story.pages[state.pageIndex].panels[index];
    const card = state.renderer.getElement(`story-card-${String(panel.number).padStart(2, '0')}`);
    if (!card) throw new Error(`[Story intro] 컷이 없습니다: ${panel.number}`);
    state.index = index;
    card.classList.add('story-panel-enter');
    state.renderer.update({ story: {
      [`panel${String(panel.number).padStart(2, '0')}`]: true,
      nextReady: true,
    } });
  };
  const advance = async () => {
    if (!state || state.index < 0) return;
    if (state.index < 3) {
      showPanel(state.index + 1);
      return;
    }
    const finishing = state.pageIndex === 1;
    if (finishing) complete();
    else stop();
    await flow.fire(finishing ? 'story.finish' : 'story.pageComplete');
  };

  flow.defineCondition('story.firstEntry', () =>
    isReady() && (replay || localStorage.getItem(storageKey) !== '1'));
  flow.defineCondition('story.complete', () => state ? complete() : false);
  // Seed visibility before show(): no flash of unread panels or next on first entry.
  const hiddenPanels = Object.fromEntries(story.pages.flatMap(page => page.panels)
    .map(panel => [`panel${String(panel.number).padStart(2, '0')}`, false]));
  flow.update({ story: { ...hiddenPanels, nextReady: false } });
  flow.on('scene:enter', ({ sceneUuid, renderer, popup }) => {
    if (popup) return;
    stop();
    const pageIndex = STORY_INTRO_SCENE_UUIDS.indexOf(sceneUuid);
    if (pageIndex < 0) return;
    const pageNumber = String(pageIndex + 1).padStart(2, '0');
    const firstCardId = `story-card-${String(story.pages[pageIndex].panels[0].number).padStart(2, '0')}`;
    renderer.update({ story: { ...hiddenPanels, nextReady: false } });
    state = { pageIndex, renderer, firstCardId, index: -1,
      startAt: performance.now() + story.motion.initialDelayMs };
    unsubscribeAdvance = renderer.on(`story-advance-${pageNumber}:click`, advance);
    for (const action of ['skip', 'next']) {
      const stableId = `story-${action}-${pageNumber}`;
      const button = renderer.getElement(stableId);
      if (!button) throw new Error(`[Story intro] 버튼이 없습니다: ${stableId}`);
      button.setAttribute('role', 'button');
      button.setAttribute('tabindex', '0');
      button.setAttribute('aria-label', action);
      button.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        button.click();
      });
    }
    frame = requestAnimationFrame(tick);
  });
}
