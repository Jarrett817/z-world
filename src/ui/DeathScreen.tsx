import { Game } from '../game/core/Game';
import { useGameState } from './HudBar';

export function DeathScreen() {
  const state = useGameState();
  if (state.phase !== 'dead') return null;

  return (
    <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/80">
      <div className="w-[480px] rounded-lg border border-[#1e3a5f] bg-[#051a2e] p-8 text-center shadow-2xl">
        <h2 className="mb-2 text-2xl font-bold text-[#d94f3d]">房车损毁 · 旅程终结</h2>
        <p className="mb-1 text-sm text-[#e8ded2]">持续撞击让救世001彻底趴窝，四周的嘶吼声越来越近。</p>
        <p className="mb-6 text-xs text-[#7dd3fc/70]">
          抵达 {state.currentNode === 'start' ? '起点' : state.currentNode} · 同行者 {state.team.length} 人
        </p>
        <button
          onClick={() => Game.reset()}
          className="w-full rounded bg-[#4cc9ff] py-2 font-bold text-[#161210] hover:bg-[#4cc9ff]"
        >
          重新开始
        </button>
      </div>
    </div>
  );
}
