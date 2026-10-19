import { useGameState } from './HudBar';

/** 触屏虚拟按键：把触摸映射成 Drive3D 的键盘事件（手机/平板驾驶用） */
function sendKey(key: string, down: boolean) {
  window.dispatchEvent(new KeyboardEvent(down ? 'keydown' : 'keyup', { key }));
}

function HoldBtn({
  label,
  sub,
  k,
  className = '',
}: {
  label: string;
  sub?: string;
  k: string;
  className?: string;
}) {
  return (
    <button
      type="button"
      className={`pointer-events-auto flex h-16 w-16 select-none flex-col items-center justify-center rounded-full border border-cyan-300/30 bg-cyan-950/40 text-cyan-100/90 backdrop-blur-sm active:bg-cyan-400/30 ${className}`}
      onTouchStart={(e) => {
        e.preventDefault();
        sendKey(k, true);
      }}
      onTouchEnd={(e) => {
        e.preventDefault();
        sendKey(k, false);
      }}
      onMouseDown={() => sendKey(k, true)}
      onMouseUp={() => sendKey(k, false)}
      onMouseLeave={() => sendKey(k, false)}
    >
      <span className="text-lg font-semibold leading-none">{label}</span>
      {sub && <span className="mt-0.5 text-[9px] leading-none text-cyan-200/60">{sub}</span>}
    </button>
  );
}

function TapBtn({
  label,
  k,
  className = '',
}: {
  label: string;
  k: string;
  className?: string;
}) {
  return (
    <button
      type="button"
      className={`pointer-events-auto flex h-11 w-11 select-none items-center justify-center rounded-full border border-cyan-300/30 bg-cyan-950/40 text-sm text-cyan-100/90 backdrop-blur-sm active:bg-cyan-400/30 ${className}`}
      onTouchStart={(e) => {
        e.preventDefault();
        sendKey(k, true);
        setTimeout(() => sendKey(k, false), 120);
      }}
      onMouseDown={() => {
        sendKey(k, true);
        setTimeout(() => sendKey(k, false), 120);
      }}
    >
      {label}
    </button>
  );
}

export function TouchControls() {
  const state = useGameState();
  if (state.phase !== 'driving') return null;

  return (
    <div className="pointer-events-none absolute inset-0 z-20 hidden pointer-coarse:block">
      {/* 左下：油门 / 刹车 */}
      <div className="absolute bottom-6 left-4 flex gap-3">
        <HoldBtn label="油门" k="d" />
        <HoldBtn label="刹车" k="a" />
      </div>
      {/* 右下：左右躲避 */}
      <div className="absolute bottom-6 right-4 flex gap-3">
        <HoldBtn label="←" sub="左躲" k="q" />
        <HoldBtn label="→" sub="右躲" k="e" />
      </div>
      {/* 右上：视角 / 停车 / 处理 */}
      <div className="absolute right-3 top-16 flex flex-col gap-2">
        <TapBtn label="车外" k="1" />
        <TapBtn label="车内" k="2" />
        <TapBtn label="车顶" k="3" />
        <TapBtn label="停车" k="p" />
        <TapBtn label="处理" k=" " />
      </div>
    </div>
  );
}
