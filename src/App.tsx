import { useEffect, useRef } from 'react';
import { createGame } from './game/PhaserGame';
import { HudBar } from './ui/HudBar';
import { EventDialog } from './ui/EventDialog';
import { TeamPanel } from './ui/TeamPanel';

export function App() {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    const game = createGame(containerRef.current);
    return () => game.destroy(true);
  }, []);

  return (
    <div className="relative h-full w-full">
      {/* Phaser 画布层 */}
      <div ref={containerRef} className="absolute inset-0" />
      {/* React UI 覆盖层 */}
      <HudBar />
      <EventDialog />
      <TeamPanel />
    </div>
  );
}
