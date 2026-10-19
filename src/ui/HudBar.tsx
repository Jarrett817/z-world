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
    <div className="pointer-events-none absolute left-0 right-0 top-0 z-10 flex items-center justify-between border-b border-[#38bdf8]/30 bg-[#051a2e]/60 px-6 py-3 backdrop-blur-md shadow-[0_0_24px_rgba(56,189,248,0.12)_inset]">
      <div className="flex items-center gap-3">
        <span className="text-lg font-bold text-[#4cc9ff] drop-shadow-[0_0_6px_rgba(76,201,255,0.6)]">{chapter.name}</span>
        <span className="text-sm text-[#7dd3fc]/70">· {node?.name}</span>
      </div>
      <div className="flex items-center gap-5 text-sm text-[#bae6fd]">
        <span className="text-[#4cc9ff]">
          📅 D{state.day} {String(hh).padStart(2, '0')}:{String(mm).padStart(2, '0')}
        </span>
        <span>🥫 食物 <b className="text-[#4cc9ff]">{state.food}</b></span>
        <span>⚡ 体力 <b className="text-[#4cc9ff]">{state.stamina}</b></span>
        <span>🔥 士气 <b className="text-[#4cc9ff]">{state.morale}</b></span>
        <span>⛽ 燃料 <b className="text-[#4cc9ff]">{Math.floor(state.fuel)}</b></span>
        <span>🛠 维修套件 <b className="text-[#4cc9ff]">{state.repairKit}</b></span>
        <button
          onClick={onOpenRV}
          className="pointer-events-auto ml-3 rounded border border-[#38bdf8]/40 px-3 py-1 text-xs text-[#7dd3fc] hover:border-[#4cc9ff] hover:text-[#4cc9ff] hover:bg-[#38bdf8]/10"
        >
          房车
        </button>
        <button
          onClick={() => Game.reset()}
          className="pointer-events-auto rounded border border-[#38bdf8]/40 px-3 py-1 text-xs text-[#7dd3fc] hover:border-[#4cc9ff] hover:text-[#4cc9ff] hover:bg-[#38bdf8]/10"
        >
          重置
        </button>
      </div>
    </div>
  );
}
