import { createRoot } from 'react-dom/client';
import './index.css';
import { App } from './App';

// 注意：不使用 StrictMode——其 double-mount 会导致 Phaser.Game 重复创建/销毁
createRoot(document.getElementById('root')!).render(<App />);
