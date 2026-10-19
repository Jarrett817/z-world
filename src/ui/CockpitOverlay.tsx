import { useEffect, useState } from 'react';

type CamMode = 'chase' | 'cockpit' | 'rooftop';

/**
 * 舱内视角挡风玻璃框：车体在舱内视角被隐藏后，
 * 用晶蓝科技风 A 柱 / 仪表台 / 方向盘补"坐在车里"的视觉。
 * 监听 Drive3D 的 zcam 事件（React 层 DOM，保证合成可见）。
 */
export function CockpitOverlay() {
  const [cam, setCam] = useState<CamMode>('chase');

  useEffect(() => {
    const onCam = (e: Event) => setCam((e as CustomEvent<CamMode>).detail);
    window.addEventListener('zcam', onCam);
    return () => window.removeEventListener('zcam', onCam);
  }, []);

  if (cam !== 'cockpit') return null;

  return (
    <div className="pointer-events-none absolute inset-0 z-30 select-none">
      {/* 挡风玻璃整体渐晕 */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_40%,rgba(76,201,255,0.07),transparent_64%)]" />
      {/* A 柱 + 顶横梁 + 仪表台（独立四边，无 clip-path） */}
      <div className="absolute left-0 top-0 bottom-0 w-[30px] bg-gradient-to-r from-[#081e34]/95 to-[#081e34]/60 shadow-[inset_-2px_0_0_rgba(76,201,255,0.4)]" />
      <div className="absolute right-0 top-0 bottom-0 w-[30px] bg-gradient-to-l from-[#081e34]/95 to-[#081e34]/60 shadow-[inset_2px_0_0_rgba(76,201,255,0.4)]" />
      <div className="absolute left-0 top-0 right-0 h-[46px] bg-gradient-to-b from-[#081e34]/95 to-[#081e34]/55 shadow-[inset_0_-2px_0_rgba(76,201,255,0.4)]" />
      <div className="absolute left-0 right-0 bottom-0 h-[34px] bg-gradient-to-t from-[#081e34]/95 to-[#081e34]/60 shadow-[inset_0_2px_0_rgba(76,201,255,0.4)]" />
      {/* 方向盘 */}
      <div className="absolute bottom-[42px] left-1/2 h-[160px] w-[160px] -translate-x-1/2 rounded-full border-[15px] border-cyan-400/35 bg-[radial-gradient(circle,rgba(76,201,255,0.08),transparent_62%)] shadow-[0_0_28px_rgba(76,201,255,0.25)]" />
      {/* 仪表台光带 */}
      <div className="absolute bottom-[8px] left-[10%] right-[10%] h-[12px] rounded-[4px] bg-gradient-to-r from-transparent via-cyan-400/55 to-transparent blur-[2px]" />
    </div>
  );
}
