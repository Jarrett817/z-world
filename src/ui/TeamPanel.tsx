import { useGameState } from './HudBar';

export function TeamPanel() {
  const state = useGameState();

  return (
    <div className="absolute bottom-4 right-4 w-64 rounded-lg border border-[#38bdf8/40] bg-[#051a2e]/90 p-4">
      <h3 className="mb-3 text-sm font-bold text-[#4cc9ff]">
        车上的人（{state.team.length}）
      </h3>
      {state.team.length === 0 ? (
        <p className="text-xs text-[#7dd3fc/70]">还没有同伴。路上会遇到。</p>
      ) : (
        <div className="flex flex-col gap-2">
          {state.team.map((m) => (
            <div key={m.id} className="flex gap-3 rounded border border-[#38bdf8/40] bg-[#1a1614] p-3">
              {m.avatar && (
                <img
                  src={m.avatar}
                  alt={m.name}
                  className="h-14 w-14 shrink-0 rounded border border-[#38bdf8/40] object-cover object-top"
                />
              )}
              <div className="min-w-0">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="font-bold text-[#e8ded2]">{m.name}</span>
                  <span className="text-xs text-[#4cc9ff]">{m.title}</span>
                </div>
                <p className="mt-1 text-xs leading-relaxed text-[#7dd3fc/70]">{m.desc}</p>
                <div className="mt-2 flex gap-3 text-xs text-[#7dd3fc/70]">
                  <span>技能·{m.skill}</span>
                  <span>攻{m.atk}</span>
                  <span>医{m.med}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
