import { useGameState } from './HudBar';
import { Game } from '../game/core/Game';

const btnBase =
  'rounded border px-3 py-2 text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-40 ' +
  'border-[#38bdf8]/40 text-[#e0f2fe] hover:border-[#4cc9ff] hover:text-[#4cc9ff] hover:bg-[#38bdf8]/10';

export function DrivePanel() {
  const state = useGameState();
  if (state.phase !== 'driving' || !state.parked) return null;

  const hh = Math.floor(state.hour);
  const mm = Math.floor((state.hour - hh) * 60);
  const canCook = state.food >= 2;
  const canRepair = state.repairKit >= 1 && state.durability < 100;

  return (
    <div className="absolute bottom-36 left-1/2 z-20 w-[440px] -translate-x-1/2 rounded-lg border border-[#38bdf8]/35 bg-[#051a2e]/40 p-5 shadow-[0_0_40px_rgba(56,189,248,0.18),0_0_24px_rgba(56,189,248,0.12)_inset] backdrop-blur-xl">
      <div className="mb-3 flex items-center justify-between border-b border-[#38bdf8]/20 pb-2">
        <h3 className="text-lg font-bold text-[#4cc9ff] drop-shadow-[0_0_6px_rgba(76,201,255,0.6)]">房车经营 · 停车中</h3>
        <span className="text-sm text-[#7dd3fc]/80">
          D{state.day} {String(hh).padStart(2, '0')}:{String(mm).padStart(2, '0')}
        </span>
      </div>
      <div className="mb-4 grid grid-cols-4 gap-2 text-center text-sm text-[#bae6fd]">
        <div>
          食物 <b className="text-[#4cc9ff]">{state.food}</b>
        </div>
        <div>
          体力 <b className="text-[#4cc9ff]">{state.stamina}</b>
        </div>
        <div>
          士气 <b className="text-[#4cc9ff]">{state.morale}</b>
        </div>
        <div>
          耐久 <b className="text-[#4cc9ff]">{Math.round(state.durability)}%</b>
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
      <div className="mt-3 text-xs text-[#7dd3fc]/70">
        维修套件 ×{state.repairKit}
        {state.team.length > 0 && <> · 队友：{state.team.map((m) => m.name).join('、')}</>}
      </div>
      <button
        onClick={() => Game.togglePark()}
        className="mt-3 w-full rounded border border-[#4cc9ff]/60 bg-[#38bdf8]/10 px-3 py-2 text-sm font-bold text-[#4cc9ff] transition-colors hover:bg-[#38bdf8]/20 shadow-[0_0_16px_rgba(56,189,248,0.25)]"
      >
        继续行驶（P）
      </button>
    </div>
  );
}
