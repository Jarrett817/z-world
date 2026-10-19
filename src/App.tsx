import { useEffect, useState } from 'react';
import { Drive3DView } from './game/three/Drive3DView';
import { HudBar } from './ui/HudBar';
import { EventDialog } from './ui/EventDialog';
import { TeamPanel } from './ui/TeamPanel';
import { ProfessionSelect } from './ui/ProfessionSelect';
import { RVPanel } from './ui/RVPanel';
import { RouteChoice } from './ui/RouteChoice';
import { DeathScreen } from './ui/DeathScreen';
import { DrivePanel } from './ui/DrivePanel';
import { TouchControls } from './ui/TouchControls';
import { OrientationHint } from './ui/OrientationHint';
import { CockpitOverlay } from './ui/CockpitOverlay';

export function App() {
  const [showRV, setShowRV] = useState(false);

  return (
    <div className="relative h-full w-full">
      {/* Three.js 3D 驾驶画布层 */}
      <Drive3DView />
      {/* React UI 覆盖层 */}
      <HudBar onOpenRV={() => setShowRV(true)} />
      <EventDialog />
      <TeamPanel />
      <RouteChoice />
      <DrivePanel />
      <TouchControls />
      <CockpitOverlay />
      <OrientationHint />
      {showRV && <RVPanel onClose={() => setShowRV(false)} />}
      <ProfessionSelect />
      <DeathScreen />
    </div>
  );
}
