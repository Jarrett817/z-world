import Phaser from 'phaser';
import { Game } from '../core/Game';
import { DataLoader } from '../core/DataLoader';

const W = 1280;
const H = 720;
const ROAD_Y = 560; // 路面顶边
const RV_X = 400; // 房车横向固定位置
const MAX_SPEED = 80; // km/h
const ACCEL = 40; // km/h 每秒
const BRAKE = 90;
const DRAG = 8;
const PX_PER_KMH = 6; // 近景滚动像素速度系数

export class DriveScene extends Phaser.Scene {
  private far!: Phaser.GameObjects.TileSprite;
  private mid!: Phaser.GameObjects.TileSprite;
  private road!: Phaser.GameObjects.Graphics;
  private rv!: Phaser.GameObjects.Container;
  private wheelL!: Phaser.GameObjects.Graphics;
  private wheelR!: Phaser.GameObjects.Graphics;
  private dash!: Phaser.GameObjects.Text;
  private hint!: Phaser.GameObjects.Text;
  private pedalGas!: Phaser.GameObjects.Container;
  private pedalBrake!: Phaser.GameObjects.Container;

  private speed = 0; // km/h
  private gasHeld = false;
  private brakeHeld = false;
  private dashPhase = 0; // 路面虚线相位

  constructor() {
    super('DriveScene');
  }

  preload(): void {
    this.load.image('far', '/assets/parallax_far.jpg');
    this.load.image('mid', '/assets/parallax_mid.jpg');
  }

  create(): void {
    // 远景：城市剪影（图裁后 3380x1140，缩放到高 500，慢速）
    this.far = this.add.tileSprite(0, 0, W, 500, 'far').setOrigin(0, 0);
    this.far.setTileScale(500 / 1140, 500 / 1140);

    // 中景：路边废墟（缩放到高 380，贴路面上沿）
    this.mid = this.add.tileSprite(0, ROAD_Y - 300, W, 380, 'mid').setOrigin(0, 0);
    this.mid.setTileScale(380 / 1140, 380 / 1140);

    // 路面
    this.road = this.add.graphics();

    // 房车剪影
    this.rv = this.buildRV();

    // 仪表盘文本（速度 + 里程）
    this.dash = this.add
      .text(W - 24, 86, '', { fontSize: '28px', color: '#e8ded2', fontStyle: 'bold' })
      .setOrigin(1, 0)
      .setDepth(10);
    this.hint = this.add
      .text(W / 2, 86, '', { fontSize: '16px', color: '#d4a05a' })
      .setOrigin(0.5, 0)
      .setDepth(10);

    // 踏板
    this.pedalGas = this.buildPedal(W - 150, H - 70, '油门', () => this.gasHeld = true, () => this.gasHeld = false);
    this.pedalBrake = this.buildPedal(150, H - 70, '刹车', () => this.brakeHeld = true, () => this.brakeHeld = false);

    // 键盘
    this.input.keyboard?.on('keydown-D', () => (this.gasHeld = true));
    this.input.keyboard?.on('keyup-D', () => (this.gasHeld = false));
    this.input.keyboard?.on('keydown-RIGHT', () => (this.gasHeld = true));
    this.input.keyboard?.on('keyup-RIGHT', () => (this.gasHeld = false));
    this.input.keyboard?.on('keydown-A', () => (this.brakeHeld = true));
    this.input.keyboard?.on('keyup-A', () => (this.brakeHeld = false));
    this.input.keyboard?.on('keydown-LEFT', () => (this.brakeHeld = true));
    this.input.keyboard?.on('keyup-LEFT', () => (this.brakeHeld = false));
  }

  private buildPedal(
    x: number,
    y: number,
    label: string,
    onDown: () => void,
    onUp: () => void,
  ): Phaser.GameObjects.Container {
    const g = this.add.graphics();
    g.fillStyle(0x2a2320, 0.9);
    g.fillRoundedRect(-90, -34, 180, 68, 10);
    g.lineStyle(2, 0x4a3f35, 1);
    g.strokeRoundedRect(-90, -34, 180, 68, 10);
    const t = this.add.text(0, 0, label, { fontSize: '20px', color: '#8a7d6d' }).setOrigin(0.5);
    const c = this.add.container(x, y, [g, t]).setDepth(10);
    c.setSize(180, 68);
    c.setInteractive({ useHandCursor: true });
    c.on('pointerdown', () => {
      onDown();
      g.clear();
      g.fillStyle(0x3d332b, 0.95);
      g.fillRoundedRect(-90, -34, 180, 68, 10);
      g.lineStyle(2, 0xe8862e, 1);
      g.strokeRoundedRect(-90, -34, 180, 68, 10);
      t.setColor('#e8862e');
    });
    const release = () => {
      onUp();
      g.clear();
      g.fillStyle(0x2a2320, 0.9);
      g.fillRoundedRect(-90, -34, 180, 68, 10);
      g.lineStyle(2, 0x4a3f35, 1);
      g.strokeRoundedRect(-90, -34, 180, 68, 10);
      t.setColor('#8a7d6d');
    };
    c.on('pointerup', release);
    c.on('pointerout', release);
    return c;
  }

  private buildRV(): Phaser.GameObjects.Container {
    const body = this.add.graphics();
    // 车身剪影
    body.fillStyle(0x0d0a08, 1);
    body.fillRoundedRect(-130, -120, 260, 100, 12);
    // 车顶空调
    body.fillRect(-60, -134, 70, 14);
    // 驾驶舱斜面
    body.fillTriangle(130, -20, 130, -96, 168, -20);
    // 车窗：篝火橙暖光
    body.fillStyle(0xe8862e, 0.9);
    body.fillRoundedRect(-110, -100, 46, 34, 4);
    body.fillRoundedRect(-54, -100, 46, 34, 4);
    body.fillRoundedRect(2, -100, 46, 34, 4);
    body.fillRoundedRect(58, -100, 46, 34, 4);
    // 大灯
    body.fillStyle(0xf0c060, 1);
    body.fillCircle(166, -26, 6);

    // 车灯光柱
    const beam = this.add.graphics();
    beam.fillStyle(0xe8a04c, 0.07);
    beam.fillTriangle(168, -26, 560, -60, 560, 20);

    // 车轮
    const mkWheel = (x: number): Phaser.GameObjects.Graphics => {
      const w = this.add.graphics();
      w.fillStyle(0x0d0a08, 1);
      w.fillCircle(0, 0, 26);
      w.lineStyle(4, 0x3d332b, 1);
      w.strokeCircle(0, 0, 26);
      w.lineStyle(3, 0x6b5d4f, 1);
      for (let i = 0; i < 4; i++) {
        const a = (Math.PI / 2) * i;
        w.lineBetween(0, 0, Math.cos(a) * 22, Math.sin(a) * 22);
      }
      w.setPosition(x, 0);
      return w;
    };
    this.wheelL = mkWheel(-80);
    this.wheelR = mkWheel(80);

    const c = this.add.container(RV_X, ROAD_Y - 8, [beam, body, this.wheelL, this.wheelR]);
    return c;
  }

  update(_time: number, deltaMs: number): void {
    const dt = deltaMs / 1000;
    const state = Game.getState();
    const driving = state.phase === 'driving';

    // 速度物理
    if (driving && this.gasHeld && state.fuel > 0) this.speed += ACCEL * dt;
    else if (this.brakeHeld) this.speed -= BRAKE * dt;
    else this.speed -= DRAG * dt;
    this.speed = Phaser.Math.Clamp(this.speed, 0, MAX_SPEED);

    const pxSpeed = this.speed * PX_PER_KMH;

    // 视差滚动
    this.far.tilePositionX += pxSpeed * 0.15 * dt;
    this.mid.tilePositionX += pxSpeed * 0.5 * dt;

    // 路面与虚线
    this.dashPhase = (this.dashPhase + pxSpeed * dt) % 80;
    this.road.clear();
    this.road.fillStyle(0x1a1512, 1);
    this.road.fillRect(0, ROAD_Y, W, H - ROAD_Y);
    this.road.lineStyle(2, 0x2a2320, 1);
    this.road.lineBetween(0, ROAD_Y, W, ROAD_Y);
    this.road.fillStyle(0x4a3f35, 1);
    for (let x = -this.dashPhase; x < W; x += 80) {
      this.road.fillRect(x, ROAD_Y + 78, 44, 6);
    }

    // 房车动效：悬挂起伏 + 车轮转动
    const speedRatio = this.speed / MAX_SPEED;
    this.rv.y = ROAD_Y - 8 + Math.sin(_time / 90) * 2.2 * speedRatio;
    const wheelSpin = (pxSpeed * dt) / 26;
    this.wheelL.rotation += wheelSpin;
    this.wheelR.rotation += wheelSpin;

    // 里程推进
    if (driving && this.speed > 0) {
      Game.driveTick((this.speed / 3600) * dt);
    }

    // 仪表
    const t = state.travel;
    if (driving && t) {
      this.dash.setText(`${Math.round(this.speed)} km/h`);
      this.hint.setText(`→ ${DataLoader.getNode(t.to)?.name ?? ''}　${t.done.toFixed(1)} / ${t.km} km`);
    } else {
      this.dash.setText('驻车');
      this.hint.setText('');
    }
    this.pedalGas.setVisible(driving);
    this.pedalBrake.setVisible(driving);
  }
}
