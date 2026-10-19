import { Game } from '../game/core/Game';
import { DataLoader } from '../game/core/DataLoader';
import { useGameState } from './HudBar';

export function ProfessionSelect() {
  const state = useGameState();
  if (state.profession) return null;

  return (
    <div className="absolute inset-0 z-50 flex items-center justify-center bg-[#161210]">
      <div className="w-[560px]">
        <h1 className="mb-2 text-center text-2xl font-bold text-[#4cc9ff]">
          末世：我要当救世主
        </h1>
        <p className="mb-8 text-center text-sm text-[#7dd3fc/70]">
          警报响了三天，城市静了三天。下楼之前，先想想——你是谁？
        </p>
        <div className="grid grid-cols-2 gap-3">
          {DataLoader.getProfessions().map((p) => (
            <button
              key={p.id}
              onClick={() => Game.chooseProfession(p.id)}
              className="rounded-lg border border-[#38bdf8/40] bg-[#051a2e] p-4 text-left hover:border-[#4cc9ff]"
            >
              <div className="mb-1 font-bold text-[#e8ded2]">{p.name}</div>
              <p className="text-xs leading-relaxed text-[#7dd3fc/70]">{p.desc}</p>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
