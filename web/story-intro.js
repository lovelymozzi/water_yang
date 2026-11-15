// Story UI uses SceneRenderer contracts and FlowDriver edges; no manual scene switching.
export const STORY_INTRO_SCENES = Object.freeze(['StoryIntro01', 'StoryIntro02']);
export const STORY_INTRO_SCENE_UUIDS = Object.freeze([
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb401',
  '91b7f29b-8b6d-41b7-a08a-99a0a1dfb402',
]);
export const STORY_INTRO_STORAGE_SUFFIX = 'story_cat_liquid_seen_v1';

export function attachStoryIntro(flow, { storageKey, isReady, saveGame, replay = false }) {
  flow.defineCondition('story.firstEntry', () =>
    isReady() && (replay || localStorage.getItem(storageKey) !== '1'));
  flow.defineCondition('story.complete', () => {
    localStorage.setItem(storageKey, '1');
    void saveGame();
    return true;
  });
  flow.on('scene:enter', ({ sceneUuid, renderer }) => {
    const pageIndex = STORY_INTRO_SCENE_UUIDS.indexOf(sceneUuid);
    if (pageIndex < 0) return;
    const pageNumber = String(pageIndex + 1).padStart(2, '0');
    for (const action of ['next', 'skip']) {
      const stableId = `story-${action}-${pageNumber}`;
      const button = renderer.getElement(stableId);
      if (!button) throw new Error(`[Story intro] 버튼이 없습니다: ${stableId}`);
      button.setAttribute('role', 'button');
      button.setAttribute('tabindex', '0');
      button.setAttribute('aria-label', action === 'skip' ? '이야기 건너뛰기'
        : pageIndex === 0 ? '다음 이야기' : '모험 시작');
      button.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        button.click();
      });
    }
  });
}
