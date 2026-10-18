import { useSyncExternalStore } from 'react';
import { Game } from '../game/core/Game';
import { DataLoader } from '../game/core/DataLoader';

export function useGameState() {
  return useSyncExternalStore(Game.subscribe, Game.getState);
}

export function HudBar() {
  const state = useGameState();
  const chapter = DataLoader.getChapter();
  const node = DataLoader.getNode(state.currentNode);

  return (
    <div className="pointer-events-none absolute left-0 right-0 top-0 flex items-center justify-between bg-[#2a2320]/90 px-6 py-3 border-b border-[#4a3f35]">
      <div className="flex items-center gap-3">
        <span className="text-lg font-bold text-[#e8862e]">{chapter.name}</span>
        <span className="text-sm text-[#8a7d6d]">· {node?.name}</span>
      </div>
      <div className="flex items-center gap-5 text-sm">
        <span>🥫 食物 <b className="text-[#e8862e]">{state.food}</b></span>
        <span>⚡ 体力 <b className="text-[#e8862e]">{state.stamina}</b></span>
        <span>🔥 士气 <b className="text-[#e8862e]">{state.morale}</b></span>
        <button
          onClick={() => Game.reset()}
          className="pointer-events-auto ml-3 rounded border border-[#4a3f35] px-3 py-1 text-xs text-[#8a7d6d] hover:border-[#e8862e] hover:text-[#e8862e]"
        >
          重置
        </button>
      </div>
    </div>
  );
}
