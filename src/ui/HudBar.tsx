import { useSyncExternalStore } from 'react';
import { CalendarDays, Apple, Zap, Flame, Fuel, Wrench, Home, RotateCcw } from 'lucide-react';
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

  const items = [
    { icon: Apple, label: '食物', value: state.food },
    { icon: Zap, label: '体力', value: state.stamina },
    { icon: Flame, label: '士气', value: state.morale },
    { icon: Fuel, label: '燃料', value: Math.floor(state.fuel) },
    { icon: Wrench, label: '维修套件', value: state.repairKit },
  ];

  return (
    <div className="pointer-events-none absolute left-0 right-0 top-0 z-10 flex items-center justify-between border-b border-[#38bdf8]/25 bg-[#051a2e]/25 px-3 py-2 backdrop-blur-md shadow-[0_0_24px_rgba(56,189,248,0.1)_inset] lg:px-6 lg:py-3">
      <div className="flex min-w-0 items-center gap-3">
        <span className="truncate text-base font-bold text-[#4cc9ff] drop-shadow-[0_0_6px_rgba(76,201,255,0.6)] lg:text-lg">{chapter.name}</span>
        <span className="hidden text-sm text-[#7dd3fc]/70 sm:block">· {node?.name}</span>
      </div>
      <div className="flex items-center gap-2 text-xs text-[#bae6fd] lg:gap-5 lg:text-sm">
        <span className="flex items-center gap-1.5 text-[#4cc9ff]">
          <CalendarDays size={15} /> D{state.day} {String(hh).padStart(2, '0')}:{String(mm).padStart(2, '0')}
        </span>
        {items.map((it) => (
          <span key={it.label} className="flex items-center gap-1.5">
            <it.icon size={15} className="text-[#7dd3fc]" /> <span className="hidden sm:inline">{it.label}</span>{' '}
            <b className="text-[#4cc9ff]">{it.value}</b>
          </span>
        ))}
        <button
          onClick={onOpenRV}
          className="pointer-events-auto ml-1 flex items-center gap-1.5 rounded border border-[#38bdf8]/40 px-2 py-1 text-xs text-[#7dd3fc] hover:border-[#4cc9ff] hover:text-[#4cc9ff] hover:bg-[#38bdf8]/10 lg:ml-3 lg:px-3"
        >
          <Home size={13} /> <span className="hidden sm:inline">房车</span>
        </button>
        <button
          onClick={() => Game.reset()}
          className="pointer-events-auto flex items-center gap-1.5 rounded border border-[#38bdf8]/40 px-2 py-1 text-xs text-[#7dd3fc] hover:border-[#4cc9ff] hover:text-[#4cc9ff] hover:bg-[#38bdf8]/10 lg:px-3"
        >
          <RotateCcw size={13} /> <span className="hidden sm:inline">重置</span>
        </button>
      </div>
    </div>
  );
}
