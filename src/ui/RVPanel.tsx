import { useState } from 'react';
import { Game } from '../game/core/Game';
import { DataLoader, Facility } from '../game/core/DataLoader';
import { useGameState } from './HudBar';

const CELL = 56;

function effectText(f: Facility): string {
  const parts: string[] = [];
  if (f.effect.staminaMax) parts.push(`体力上限+${f.effect.staminaMax}`);
  if (f.effect.foodMax) parts.push(`食物上限+${f.effect.foodMax}`);
  if (f.effect.staminaPerMove) parts.push(`每次移动体力+${f.effect.staminaPerMove}`);
  return parts.join(' · ');
}

export function RVPanel({ onClose }: { onClose: () => void }) {
  const state = useGameState();
  const cfg = DataLoader.getRvConfig();
  const [selected, setSelected] = useState<string | null>(null);

  const facilities = Object.values(cfg.facilities);

  return (
    <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/70">
      <div className="rounded-lg border border-[#4a3f35] bg-[#2a2320] p-6">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold text-[#e8862e]">房车内部</h2>
          <button
            onClick={onClose}
            className="rounded border border-[#4a3f35] px-3 py-1 text-xs text-[#8a7d6d] hover:border-[#e8862e] hover:text-[#e8862e]"
          >
            关闭
          </button>
        </div>

        {/* 车厢网格（背景：房车内部实景） */}
        <div
          className="relative overflow-hidden rounded border-2 border-[#4a3f35]"
          style={{ width: cfg.gridWidth * CELL, height: cfg.gridHeight * CELL }}
        >
          <img
            src="/assets/rv_interior.jpg"
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
          <div className="absolute inset-0 bg-[#161210]/45" />
          {/* 格子线 */}
          {Array.from({ length: cfg.gridWidth * cfg.gridHeight }, (_, i) => {
            const x = i % cfg.gridWidth;
            const y = Math.floor(i / cfg.gridWidth);
            return (
              <div
                key={i}
                onClick={() => selected && Game.placeFacility(selected, x, y)}
                className={`absolute border border-[#2a2320] ${selected ? 'cursor-pointer hover:bg-[#e8862e]/10' : ''}`}
                style={{ left: x * CELL, top: y * CELL, width: CELL, height: CELL }}
              />
            );
          })}
          {/* 已放置设施 */}
          {state.rvLayout.map((p, i) => {
            const f = DataLoader.getFacility(p.facilityId);
            if (!f) return null;
            return (
              <div
                key={i}
                onClick={() => Game.removeFacilityAt(p.x, p.y)}
                title={`${f.name}（点击拆除）`}
                className="absolute flex cursor-pointer items-center justify-center rounded border border-[#e8862e]/50 bg-[#e8862e]/15 text-xs text-[#e8862e] hover:bg-red-900/30 hover:text-red-300"
                style={{ left: p.x * CELL, top: p.y * CELL, width: f.w * CELL, height: f.h * CELL }}
              >
                {f.name}
              </div>
            );
          })}
        </div>

        <p className="mt-2 text-xs text-[#8a7d6d]">
          {selected ? '点击空格放置 · 点击已放置设施拆除' : '先在下方选择要放置的设施'}
        </p>

        {/* 设施列表 */}
        <div className="mt-4 grid grid-cols-4 gap-2">
          {facilities.map((f) => (
            <button
              key={f.id}
              onClick={() => setSelected(selected === f.id ? null : f.id)}
              className={`rounded border p-3 text-left ${
                selected === f.id
                  ? 'border-[#e8862e] bg-[#e8862e]/10'
                  : 'border-[#4a3f35] hover:border-[#e8862e]/60'
              }`}
            >
              <div className="text-sm font-bold text-[#e8ded2]">
                {f.name} <span className="text-xs font-normal text-[#8a7d6d]">{f.w}×{f.h}</span>
              </div>
              <p className="mt-1 text-xs text-[#8a7d6d]">{f.desc}</p>
              {effectText(f) && (
                <p className="mt-1 text-xs text-[#e8862e]">{effectText(f)}</p>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
