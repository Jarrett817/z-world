import { Game } from '../game/core/Game';
import { DataLoader } from '../game/core/DataLoader';
import { useGameState } from './HudBar';

export function RouteChoice() {
  const state = useGameState();
  if (state.phase !== 'route') return null;

  const routes = Game.getRoutes();
  if (routes.length === 0) return null;

  return (
    <div className="absolute inset-x-0 bottom-0 z-20 flex flex-col items-center gap-3 pb-10">
      <div className="text-sm tracking-widest text-[#d4a05a]">接下来去哪儿？</div>
      <div className="flex gap-4">
        {routes.map((r) => {
          const node = DataLoader.getNode(r.to);
          return (
            <button
              key={r.to}
              onClick={() => Game.chooseRoute(r.to)}
              className="rounded-lg border border-[#38bdf8/40] bg-[#051a2e]/95 px-8 py-4 text-left shadow-xl transition hover:border-[#4cc9ff]"
            >
              <div className="text-lg font-bold text-[#e8ded2]">→ {node?.name}</div>
              <div className="mt-1 text-xs text-[#7dd3fc/70]">{r.km} 公里</div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
