// Local development controls live outside the published game scenes.
export function getDevStage(url, maxStage) {
  if (!['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) return null;
  const value = url.searchParams.get('devStage');
  if (value === null) return null;
  const stage = Number(value);
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(stage) || stage < 1 || stage > maxStage) {
    throw new Error(`[DEV] 레벨은 1~${maxStage} 사이의 정수여야 합니다.`);
  }
  return stage;
}

export function mountDevTools({ maxStage, getCurrentStage, isStorySeen }) {
  if (!['localhost', '127.0.0.1', '[::1]'].includes(location.hostname)) return;
  const tools = document.createElement('aside');
  tools.dataset.devTools = '';
  tools.innerHTML = `
    <details>
      <summary>DEV</summary>
      <form>
        <label for="dev-stage">시작 레벨 (1~${maxStage})</label>
        <input id="dev-stage" name="devStage" type="number" min="1" max="${maxStage}" step="1" value="${getCurrentStage()}" required>
        <button type="submit">선택 레벨 시작</button>
        <small>1레벨은 카툰부터 시작합니다.</small>
      </form>
      <p></p>
      <button type="button" data-story-replay>카툰 다시 보기</button>
    </details>`;
  tools.querySelector('details').addEventListener('toggle', () => {
    tools.querySelector('input').value = getCurrentStage();
    tools.querySelector('p').textContent = `카툰: ${isStorySeen() ? '시청 완료 · 일반 입장 시 생략' : '미시청 · 첫 입장 시 재생'}`;
  });
  tools.querySelector('form').addEventListener('submit', event => {
    event.preventDefault();
    const url = new URL(location.href);
    url.searchParams.set('devStage', tools.querySelector('input').value);
    getDevStage(url, maxStage);
    url.searchParams.delete('story');
    url.searchParams.delete('resetStage');
    location.assign(url.href);
  });
  tools.querySelector('[data-story-replay]').addEventListener('click', () => {
    const url = new URL(location.href);
    url.searchParams.delete('devStage');
    url.searchParams.delete('resetStage');
    url.searchParams.set('story', 'replay');
    location.assign(url.href);
  });
  document.body.appendChild(tools);
}
