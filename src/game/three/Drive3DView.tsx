import { useEffect, useRef } from 'react';
import { Drive3D } from './Drive3D';

export function Drive3DView() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const drive = new Drive3D(el);
    void drive.start();
    return () => drive.dispose();
  }, []);

  return <div ref={ref} className="absolute inset-0" />;
}
