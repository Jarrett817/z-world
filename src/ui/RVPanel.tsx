import { useState } from 'react';
import { motion } from 'motion/react';
import { Game } from '../game/core/Game';
import { DataLoader, Facility } from '../game/core/DataLoader';
import { useGameState } from './HudBar';

const CELL = 56;

// 幸存者工位（相对车厢网格容器的百分比位置）与当前活计
const CREW_SPOTS: Record<string, { left: string; top: string; task: string }> = {
  chen_mo: { left: '8%', top: '28%', task: '检查车况' },
  lin_wan: { left: '27%', top: '26%', task: '整理药品' },
};

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
      <div className="rounded-lg border border-[#38bdf8/40] bg-[#051a2e] p-6">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold text-[#4cc9ff]">房车内部</h2>
          <button
            onClick={onClose}
            className="rounded border border-[#38bdf8/40] px-3 py-1 text-xs text-[#7dd3fc/70] hover:border-[#4cc9ff] hover:text-[#4cc9ff]"
          >
            关闭
          </button>
        </div>

        {/* 车厢网格（背景：房车内部实景） */}
        <div
          className="relative overflow-hidden rounded border-2 border-[#38bdf8/40]"
          style={{ width: cfg.gridWidth * CELL, height: cfg.gridHeight * CELL }}
        >
          <img
            src="/assets/rv_interior.jpg"
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
          <div className="absolute inset-0 bg-[#161210]/45" />
          {/* 已招募幸存者：在各自工位忙碌 */}
          {state.team.map((m, i) => {
            const spot = CREW_SPOTS[m.id];
            if (!spot) return null;
            return (
              <motion.div
                key={m.id}
                className="pointer-events-none absolute z-10 flex -translate-x-1/2 flex-col items-center"
                style={{ left: spot.left, top: spot.top }}
                animate={{ y: [0, -3, 0] }}
                transition={{ duration: 2.4, repeat: Infinity, delay: i * 0.9, ease: 'easeInOut' }}
              >
                <img
                  src={m.avatar}
                  alt={m.name}
                  className="h-20 w-14 rounded-md border border-[#4cc9ff]/50 object-cover object-top shadow-[0_2px_8px_rgba(0,0,0,0.6)]"
                />
                <span className="mt-0.5 whitespace-nowrap rounded bg-[#161210]/85 px-1.5 py-px text-[10px] text-[#e8ded2]">
                  {m.name} · {spot.task}
                </span>
              </motion.div>
            );
          })}
          {/* 格子线 */}
          {Array.from({ length: cfg.gridWidth * cfg.gridHeight }, (_, i) => {
            const x = i % cfg.gridWidth;
            const y = Math.floor(i / cfg.gridWidth);
            return (
              <div
                key={i}
                onClick={() => selected && Game.placeFacility(selected, x, y)}
                className={`absolute border border-[#051a2e] ${selected ? 'cursor-pointer hover:bg-[#4cc9ff]/10' : ''}`}
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
                className="absolute z-20 flex cursor-pointer items-center justify-center rounded border border-[#4cc9ff]/50 bg-[#4cc9ff]/15 text-xs text-[#4cc9ff] hover:bg-red-900/30 hover:text-red-300"
                style={{ left: p.x * CELL, top: p.y * CELL, width: f.w * CELL, height: f.h * CELL }}
              >
                {f.name}
              </div>
            );
          })}
        </div>

        <p className="mt-2 text-xs text-[#7dd3fc/70]">
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
                  ? 'border-[#4cc9ff] bg-[#4cc9ff]/10'
                  : 'border-[#38bdf8/40] hover:border-[#4cc9ff]/60'
              }`}
            >
              <div className="text-sm font-bold text-[#e8ded2]">
                {f.name} <span className="text-xs font-normal text-[#7dd3fc/70]">{f.w}×{f.h}</span>
              </div>
              <p className="mt-1 text-xs text-[#7dd3fc/70]">{f.desc}</p>
              {effectText(f) && (
                <p className="mt-1 text-xs text-[#4cc9ff]">{effectText(f)}</p>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
