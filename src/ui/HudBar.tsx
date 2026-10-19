import { useSyncExternalStore } from 'react';
import { Game } from '../game/core/Game';
import { DataLoader } from '../game/core/DataLoader';

export function useGameState() {
  return useSyncExternalStore(Game.subscribe, Game.getState);
}

export function HudBar({ onOpenRV }: { onOpenRV: () => void }) {
  const state = useGameState();
  const chapter = DataLoader.getChapter();
  const node = DataLoader.getNode(state.currentNode);
  const hh = Math.floor(state.hour);
  const mm = Math.floor((state.hour - hh) * 60);

  return (
    <div className="pointer-events-none absolute left-0 right-0 top-0 z-10 flex items-center justify-between border-b border-[#4a3f35] bg-[#2a2320]/90 px-6 py-3">
      <div className="flex items-center gap-3">
        <span className="text-lg font-bold text-[#e8862e]">{chapter.name}</span>
        <span className="text-sm text-[#8a7d6d]">· {node?.name}</span>
      </div>
      <div className="flex items-center gap-5 text-sm">
        <span className="text-[#e8862e]">
          📅 D{state.day} {String(hh).padStart(2, '0')}:{String(mm).padStart(2, '0')}
        </span>
        <span>🥫 食物 <b className="text-[#e8862e]">{state.food}</b></span>
        <span>⚡ 体力 <b className="text-[#e8862e]">{state.stamina}</b></span>
        <span>🔥 士气 <b className="text-[#e8862e]">{state.morale}</b></span>
        <span>⛽ 燃料 <b className="text-[#e8862e]">{Math.floor(state.fuel)}</b></span>
        <span>🛠 维修套件 <b className="text-[#e8862e]">{state.repairKit}</b></span>
        <button
          onClick={onOpenRV}
          className="pointer-events-auto ml-3 rounded border border-[#4a3f35] px-3 py-1 text-xs text-[#8a7d6d] hover:border-[#e8862e] hover:text-[#e8862e]"
        >
          房车
        </button>
        <button
          onClick={() => Game.reset()}
          className="pointer-events-auto rounded border border-[#4a3f35] px-3 py-1 text-xs text-[#8a7d6d] hover:border-[#e8862e] hover:text-[#e8862e]"
        >
          重置
        </button>
      </div>
    </div>
  );
}
