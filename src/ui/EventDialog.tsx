import { Game } from '../game/core/Game';
import { DataLoader } from '../game/core/DataLoader';
import { useGameState } from './HudBar';

function effectLabel(e?: { food?: number; stamina?: number; morale?: number; fuel?: number }): string {
  if (!e) return '';
  const parts: string[] = [];
  const fmt = (n: number, name: string) => parts.push(`${name}${n > 0 ? '+' : ''}${n}`);
  if (e.food) fmt(e.food, '食物');
  if (e.stamina) fmt(e.stamina, '体力');
  if (e.morale) fmt(e.morale, '士气');
  if (e.fuel) fmt(e.fuel, '燃料');
  return parts.join(' · ');
}

export function EventDialog() {
  const state = useGameState();
  const ev = state.currentEvent;

  if (state.finished) {
    return (
      <div className="absolute inset-0 z-30 flex items-center justify-center bg-black/70">
        <div className="w-[560px] overflow-hidden rounded-lg border border-[#38bdf8/40] bg-[#051a2e] shadow-2xl">
          <img src="/assets/ending.jpg" alt="" className="h-56 w-full object-cover" />
          <div className="p-8">
            <h2 className="mb-3 text-xl font-bold text-[#4cc9ff]">第一章 · 完</h2>
            <p className="mb-6 leading-relaxed text-[#e8ded2]">
              城区的轮廓在晨雾里显出来。车上 {state.team.length} 个人，燃料还剩 {state.fuel}。
              路还长。
            </p>
            <button
              onClick={() => Game.reset()}
              className="w-full rounded bg-[#4cc9ff] py-2 font-bold text-[#161210] hover:bg-[#4cc9ff]"
            >
              重新开始
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (!ev) return null;

  const character = ev.character ? DataLoader.getSurvivor(ev.character) : null;

  return (
    <div className="absolute inset-0 z-30 flex items-center justify-center bg-black/70">
      <div className="w-[560px] overflow-hidden rounded-lg border border-[#38bdf8/40] bg-[#051a2e] shadow-2xl">
        {ev.image && (
          <div className="relative">
            <img src={ev.image} alt="" className="h-56 w-full object-cover" />
            <div className="absolute inset-0 bg-gradient-to-t from-[#051a2e] via-transparent to-transparent" />
            {character?.avatar && (
              <img
                src={character.avatar}
                alt={character.name}
                className="absolute -bottom-10 right-6 h-24 w-24 rounded-lg border-2 border-[#4cc9ff] object-cover object-top shadow-lg"
              />
            )}
          </div>
        )}
        <div className="p-8 pt-6">
          <h2 className="mb-1 text-xl font-bold text-[#4cc9ff]">{ev.title}</h2>
          {character && (
            <p className="mb-2 text-xs text-[#7dd3fc/70]">
              {character.name} · {character.title}
            </p>
          )}
          <p className="mb-6 mt-3 leading-relaxed text-[#e8ded2]">{ev.text}</p>
          <div className="flex flex-col gap-2">
            {ev.choices.map((c, i) => {
              const meta = [effectLabel(c.effects), c.recruit ? '可能有人加入' : '']
                .filter(Boolean)
                .join(' · ');
              return (
                <button
                  key={i}
                  onClick={() => Game.applyChoice(i)}
                  className="rounded border border-[#38bdf8/40] px-4 py-3 text-left hover:border-[#4cc9ff] hover:bg-[#1e3a5f]"
                >
                  <div className="text-[#e8ded2]">{c.text}</div>
                  {meta && <div className="mt-1 text-xs text-[#7dd3fc/70]">{meta}</div>}
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
