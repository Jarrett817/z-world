import Phaser from 'phaser';
import { Game } from '../core/Game';
import { DataLoader } from '../core/DataLoader';

const COLOR_LINE = 0x4a3f35;
const COLOR_NODE = 0x6b5d4f;
const COLOR_CURRENT = 0xe8862e;
const COLOR_REACHABLE = 0xd4a05a;
const COLOR_DONE = 0x3d332b;

export class MapScene extends Phaser.Scene {
  private layer!: Phaser.GameObjects.Container;
  private unsubscribe?: () => void;

  constructor() {
    super('MapScene');
  }

  create(): void {
    this.layer = this.add.container(0, 0);
    this.unsubscribe = Game.subscribe(() => this.redraw());
    this.redraw();
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.unsubscribe?.());
  }

  private redraw(): void {
    if (!this.scene.isActive() || !this.layer?.active) return;
    this.layer.removeAll(true);
    const state = Game.getState();
    const chapter = DataLoader.getChapter();
    const reachable = new Set(Game.getReachable());
    const visited = new Set(state.visited);
    const g = this.add.graphics();

    // 连线
    g.lineStyle(3, COLOR_LINE, 0.8);
    for (const [a, b] of chapter.edges) {
      const na = DataLoader.getNode(a);
      const nb = DataLoader.getNode(b);
      if (na && nb) g.lineBetween(na.x, na.y, nb.x, nb.y);
    }
    this.layer.add(g);

    // 节点
    for (const node of chapter.nodes) {
      const isCurrent = node.id === state.currentNode;
      const isReachable = reachable.has(node.id);
      const isDone = visited.has(node.id) && !isCurrent;

      const color = isCurrent ? COLOR_CURRENT : isReachable ? COLOR_REACHABLE : isDone ? COLOR_DONE : COLOR_NODE;
      const radius = isCurrent ? 22 : isReachable ? 18 : 14;

      const circle = this.add.circle(node.x, node.y, radius, color, isDone ? 0.5 : 1);
      if (isCurrent) circle.setStrokeStyle(3, 0xffffff, 0.8);
      this.layer.add(circle);

      const label = this.add
        .text(node.x, node.y + radius + 14, node.name, {
          fontSize: '16px',
          color: isCurrent ? '#ffffff' : isReachable ? '#e8ded2' : '#8a7d6d',
        })
        .setOrigin(0.5, 0);
      this.layer.add(label);

      if (isReachable) {
        const zone = this.add
          .zone(node.x, node.y, 88, 88)
          .setInteractive({ useHandCursor: true });
        zone.on('pointerdown', () => Game.moveTo(node.id));
        this.layer.add(zone);
      }
    }
  }
}
