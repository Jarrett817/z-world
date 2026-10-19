import { Smartphone } from 'lucide-react';

/** 竖屏引导：驾驶类游戏推荐横屏，竖屏时提示翻转（仅手机） */
export function OrientationHint() {
  return (
    <div className="pointer-events-none absolute inset-0 z-50 hidden items-center justify-center bg-[#051a2e]/85 backdrop-blur-sm portrait:flex md:hidden">
      <div className="flex flex-col items-center gap-3 px-6 text-center">
        <Smartphone className="h-10 w-10 animate-pulse text-[#4cc9ff]" />
        <p className="text-lg font-bold text-[#e0f2fe]">请横屏游玩</p>
        <p className="text-sm text-[#7dd3fc]/70">转动手机到横向，获得最佳驾驶体验</p>
      </div>
    </div>
  );
}
