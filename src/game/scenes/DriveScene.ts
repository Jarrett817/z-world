import Phaser from 'phaser';
import { Game, Weather } from '../core/Game';
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

interface Zombie {
  sprite: Phaser.GameObjects.Image;
  speed: number;
  active: boolean;
}

export class DriveScene extends Phaser.Scene {
  private far!: Phaser.GameObjects.TileSprite;
  private mid!: Phaser.GameObjects.TileSprite;
  private road!: Phaser.GameObjects.Graphics;
  private rv!: Phaser.GameObjects.Container;
  private rvBody!: Phaser.GameObjects.Sprite;
  private dash!: Phaser.GameObjects.Text;
  private hint!: Phaser.GameObjects.Text;
  private pedalGas!: Phaser.GameObjects.Container;
  private pedalBrake!: Phaser.GameObjects.Container;

  private speed = 0; // km/h
  private gasHeld = false;
  private brakeHeld = false;
  private dashPhase = 0; // 路面虚线相位

  // 丧尸
  private zombies: Zombie[] = [];
  private zombieSpawnTimer = 0;

  // 天气
  private weatherGfx!: Phaser.GameObjects.Graphics;
  private weatherOverlay!: Phaser.GameObjects.Rectangle;
  private weatherText!: Phaser.GameObjects.Text;

  constructor() {
    super('DriveScene');
  }

  preload(): void {
    this.load.image('far', '/assets/parallax_far.jpg');
    this.load.image('mid', '/assets/parallax_mid.jpg');
    for (let i = 1; i <= 8; i++) {
      this.load.image(`rv_${i}`, `/assets/rv3d/rv_0${i}.png`);
    }
    this.load.image('zombie', '/assets/zombie_walk.jpg');
  }

  create(): void {
    // 远景：城市剪影（图裁后 3380x1140，缩放到高 500，慢速）
    this.far = this.add.tileSprite(0, 0, W, 500, 'far').setOrigin(0, 0);
    this.far.setTileScale(500 / 1140, 500 / 1140);

    // 中景：路边废墟（3D 渲染 1920x720，缩放到高 380，贴路面上沿）
    this.mid = this.add.tileSprite(0, ROAD_Y - 300, W, 380, 'mid').setOrigin(0, 0);
    this.mid.setTileScale(380 / 720, 380 / 720);

    // 房车行驶动画（3D 预渲染 8 帧车轮转动序列）
    if (!this.anims.exists('rv_drive')) {
      this.anims.create({
        key: 'rv_drive',
        frames: [1, 2, 3, 4, 5, 6, 7, 8].map((i) => ({ key: `rv_${i}` })),
        frameRate: 12,
        repeat: -1,
      });
    }

    // 路面
    this.road = this.add.graphics();

    // 房车剪影
    this.rv = this.buildRV();

    // 天气层
    this.weatherOverlay = this.add
      .rectangle(0, 0, W, H, 0x000000, 0)
      .setOrigin(0, 0)
      .setDepth(5);
    this.weatherGfx = this.add.graphics().setDepth(6);
    this.weatherText = this.add
      .text(W - 24, 56, '', { fontSize: '14px', color: '#8a7d6d' })
      .setOrigin(1, 0)
      .setDepth(10);

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
    // 3D 预渲染序列帧（1280x720，车身占中间条带），显示为高 260
    const RV_H = 260;
    const S = RV_H / 720;
    const body = this.add.sprite(0, 0, 'rv_1').setOrigin(0.5, 1);
    body.setDisplaySize(1280 * S, RV_H);
    body.play('rv_drive');
    this.rvBody = body;

    // 车灯光柱（车头朝右）
    const beam = this.add.graphics();
    beam.fillStyle(0xe8a04c, 0.07);
    beam.fillTriangle(195, -68, 560, -110, 560, -20);

    return this.add.container(RV_X, ROAD_Y + 4, [beam, body]);
  }

  // ---- 丧尸系统 ----
  private spawnZombie(): void {
    // 从屏幕右侧生成，朝左走向房车
    const y = ROAD_Y + Phaser.Math.Between(-40, 60);
    const img = this.add.image(W + 60, y, 'zombie');
    img.setDisplaySize(80, 120);
    img.setDepth(3);
    this.zombies.push({
      sprite: img,
      speed: Phaser.Math.Between(25, 50),
      active: true,
    });
  }

  private updateZombies(dt: number, pxSpeed: number): void {
    const state = Game.getState();
    const driving = state.phase === 'driving';

    // 生成逻辑：仅在行驶时生成，车速越快概率越高
    if (driving && this.speed > 5) {
      this.zombieSpawnTimer -= dt;
      if (this.zombieSpawnTimer <= 0) {
        // 基础 1.5s 一只，车速加成
        const rate = 1.5 - (this.speed / MAX_SPEED) * 1.0;
        this.zombieSpawnTimer = Math.max(0.4, rate);
        this.spawnZombie();
      }
    }

    // 移动与碰撞
    const rvLeft = RV_X - 180; // 房车碰撞左边界
    for (const z of this.zombies) {
      if (!z.active) continue;
      z.sprite.x -= (z.speed + pxSpeed * 0.3) * dt;

      // 碰到房车
      if (z.sprite.x < rvLeft + 100) {
        z.active = false;
        z.sprite.destroy();
        Game.zombieAttack();
        // 撞击反馈：房车轻微震动
        this.tweens.add({
          targets: this.rv,
          x: RV_X - 8,
          duration: 60,
          yoyo: true,
          repeat: 2,
        });
        continue;
      }

      // 超出屏幕左侧
      if (z.sprite.x < -100) {
        z.active = false;
        z.sprite.destroy();
      }
    }

    // 清理已销毁的
    if (this.zombies.length > 30) {
      this.zombies = this.zombies.filter((z) => z.active);
    }
  }

  // ---- 天气系统 ----
  private renderWeather(weather: Weather, dt: number): void {
    this.weatherGfx.clear();

    // 雾：半透明覆盖
    if (weather === 'fog') {
      this.weatherOverlay.setFillStyle(0x2a2a2a, 0.35);
    } else if (weather === 'rain') {
      this.weatherOverlay.setFillStyle(0x1a2a3a, 0.15);
    } else if (weather === 'snow') {
      this.weatherOverlay.setFillStyle(0x1a1a2a, 0.12);
    } else {
      this.weatherOverlay.setFillStyle(0x000000, 0);
    }

    // 雨：斜线粒子
    if (weather === 'rain') {
      this.weatherGfx.lineStyle(1, 0x6a8aaa, 0.4);
      const count = 80;
      for (let i = 0; i < count; i++) {
        const x = (i * 37 + this.time.now * 0.5) % (W + 40) - 20;
        const y = (i * 91 + this.time.now * 0.8) % (H + 40) - 20;
        this.weatherGfx.lineBetween(x, y, x - 3, y + 12);
      }
    }

    // 雪：圆点飘落
    if (weather === 'snow') {
      this.weatherGfx.fillStyle(0xe8e8f0, 0.7);
      const count = 60;
      for (let i = 0; i < count; i++) {
        const x = (i * 53 + this.time.now * 0.12 + Math.sin(i + this.time.now * 0.001) * 30) % (W + 20) - 10;
        const y = (i * 97 + this.time.now * 0.25) % (H + 20) - 10;
        const r = 1 + (i % 3) * 0.5;
        this.weatherGfx.fillCircle(x, y, r);
      }
    }

    // 天气标签
    const labels: Record<Weather, string> = {
      clear: '晴',
      rain: '雨',
      fog: '雾',
      snow: '雪',
    };
    this.weatherText.setText(labels[weather]);
  }

  update(_time: number, deltaMs: number): void {
    const dt = deltaMs / 1000;
    const state = Game.getState();
    const driving = state.phase === 'driving';

    // 速度物理（天气影响：雨天刹车距离变长，雪天加速变慢）
    const weather = state.weather;
    let accel = ACCEL;
    let brake = BRAKE;
    if (weather === 'rain') brake = BRAKE * 0.7;
    if (weather === 'snow') accel = ACCEL * 0.6;

    if (driving && this.gasHeld && state.fuel > 0) this.speed += accel * dt;
    else if (this.brakeHeld) this.speed -= brake * dt;
    else this.speed -= DRAG * dt;
    this.speed = Phaser.Math.Clamp(this.speed, 0, MAX_SPEED);

    const pxSpeed = this.speed * PX_PER_KMH;

    // 视差滚动
    this.far.tilePositionX += pxSpeed * 0.15 * dt;
    this.mid.tilePositionX += pxSpeed * 0.5 * dt;

    // 房车动效：悬挂起伏 + 动画速度跟随车速（停车时定格）
    const speedRatio = this.speed / MAX_SPEED;
    this.rv.y = ROAD_Y + 4 + Math.sin(_time / 90) * 2.2 * speedRatio;
    if (this.speed > 1) {
      this.rvBody.anims.resume();
      this.rvBody.anims.timeScale = 0.3 + speedRatio * 1.4;
    } else {
      this.rvBody.anims.pause();
    }

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

    // 丧尸
    this.updateZombies(dt, pxSpeed);

    // 天气
    this.renderWeather(weather, dt);

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
