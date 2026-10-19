import { useGameState } from './HudBar';
import { Game } from '../game/core/Game';

const btnBase =
  'rounded border px-3 py-2 text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-40 ' +
  'border-[#4a3f35] text-[#e8ded2] hover:border-[#e8862e] hover:text-[#e8862e]';

export function DrivePanel() {
  const state = useGameState();
  if (state.phase !== 'driving' || !state.parked) return null;

  const hh = Math.floor(state.hour);
  const mm = Math.floor((state.hour - hh) * 60);
  const canCook = state.food >= 2;
  const canRepair = state.repairKit >= 1 && state.durability < 100;

  return (
    <div className="absolute bottom-36 left-1/2 z-20 w-[440px] -translate-x-1/2 rounded-lg border border-[#4a3f35] bg-[#2a2320]/95 p-5 shadow-2xl">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-lg font-bold text-[#e8862e]">房车经营 · 停车中</h3>
        <span className="text-sm text-[#8a7d6d]">
          D{state.day} {String(hh).padStart(2, '0')}:{String(mm).padStart(2, '0')}
        </span>
      </div>
      <div className="mb-4 grid grid-cols-4 gap-2 text-center text-sm">
        <div>
          食物 <b className="text-[#e8862e]">{state.food}</b>
        </div>
        <div>
          体力 <b className="text-[#e8862e]">{state.stamina}</b>
        </div>
        <div>
          士气 <b className="text-[#e8862e]">{state.morale}</b>
        </div>
        <div>
          耐久 <b className="text-[#e8862e]">{Math.round(state.durability)}%</b>
        </div>
      </div>
      <div className="flex flex-col gap-2">
        <button disabled={!canCook} onClick={() => Game.cookMeal()} className={btnBase}>
          做饭（食物-2 → 体力+3 · 士气+1）
        </button>
        <button onClick={() => Game.restInRv()} className={btnBase}>
          休息（体力+4 · 耗时 6 小时）
        </button>
        <button disabled={!canRepair} onClick={() => Game.repairWithKit()} className={btnBase}>
          维修车身（维修套件-1 → 耐久+25）
        </button>
      </div>
      <div className="mt-3 text-xs text-[#8a7d6d]">
        维修套件 ×{state.repairKit}
        {state.team.length > 0 && <> · 队友：{state.team.map((m) => m.name).join('、')}</>}
      </div>
      <button
        onClick={() => Game.togglePark()}
        className="mt-3 w-full rounded border border-[#e8862e]/60 bg-[#e8862e]/10 px-3 py-2 text-sm font-bold text-[#e8862e] transition-colors hover:bg-[#e8862e]/20"
      >
        继续行驶（P）
      </button>
    </div>
  );
}
