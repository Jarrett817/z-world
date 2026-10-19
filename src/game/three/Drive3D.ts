import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { Game, Weather } from '../core/Game';

const MAX_SPEED = 80; // km/h
const ACCEL = 40; // km/h 每秒
const BRAKE = 90;
const DRAG = 8;
const KMH_TO_UNITS = 0.5; // 驾驶尺度：km/h → 世界单位/秒
const GROUND_Y = -1.56; // 地面高度（glTF Y-up，车底贴地）
const Z_SPAWN = -260; // 世界对象生成/循环重置深度
const Z_LOOP = 40; // 对象越过此 Z 后循环回前方
const ROAD_HALF = 6.5; // 路面半宽

type CamMode = 'chase' | 'cockpit' | 'rooftop';

const CAM_HINT: Record<CamMode, string> = {
  chase: '追尾视角',
  cockpit: '舱内视角',
  rooftop: '车顶视角',
};

interface SideObj {
  group: THREE.Group;
  z: number;
  speed: number; // 仅丧尸使用（相对车的前进速度，m/s）
  kind: 'zombie' | 'prop';
  active: boolean;
  mixer?: THREE.AnimationMixer; // 丧尸动画
}

interface BlockObj {
  group: THREE.Object3D;
  z: number;
  x: number;
  kind: 'soft' | 'hard';
  active: boolean;
  hit: boolean; // 已撞击过（防重复扣耐久）
  flying: boolean; // 软路障被撞飞动画
  flyT: number;
}

const WEATHER_LABEL: Record<Weather, string> = { clear: '晴', rain: '雨', fog: '雾', snow: '雪' };

function rng(a: number, b: number): number {
  return a + Math.random() * (b - a);
}

export class Drive3D {
  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private clock = new THREE.Clock();
  private raf = 0;
  private disposed = false;

  // 相机
  private camChase = new THREE.PerspectiveCamera(55, 1, 0.1, 600);
  private camCockpit = new THREE.PerspectiveCamera(72, 1, 0.1, 600);
  private camRooftop = new THREE.PerspectiveCamera(65, 1, 0.1, 600);
  private camInterior = new THREE.PerspectiveCamera(60, 1, 0.1, 100); // 车内画中画
  private camMode: CamMode = 'chase';

  // 房车
  private rv: THREE.Group | null = null;

  // 驾驶状态
  private speed = 0;
  private prevSpeed = 0;
  private boost = 0; // 推背感：+加速前倾 / -刹车前顶，快起慢落
  private gasHeld = false;
  private brakeHeld = false;
  private steerLeft = false;
  private steerRight = false;
  private offsetX = 0; // 车辆横向偏移（躲避路障）
  private spawnTimer = 0;
  private blockTimer = 0;

  // 撞击反馈
  private shakeTime = 0;
  private shakeIntensity = 0;

  // 世界对象
  private props: SideObj[] = [];
  private blocks: BlockObj[] = [];
  private dashes: THREE.Mesh[] = [];

  // 模型源
  private zombieSource: THREE.Group | null = null;
  private zombieClips: THREE.AnimationClip[] = [];
  private softSources: THREE.Object3D[] = [];
  private hardSources: THREE.Object3D[] = [];

  // 天气
  private rain!: THREE.Points;
  private snow!: THREE.Points;
  private weather: Weather = 'clear';

  // HUD（Three 组件内部 DOM，React 只管顶层 UI）
  private telemetryEl: HTMLDivElement;
  private hintEl: HTMLDivElement;
  private pipEl: HTMLDivElement; // 车内画中画边框

  constructor(container: HTMLElement) {
    this.container = container;

    const w = container.clientWidth || 1280;
    const h = container.clientHeight || 720;
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(w, h);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    container.appendChild(this.renderer.domElement);
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';

    this.scene.background = new THREE.Color(0x1c1a18);
    this.scene.fog = new THREE.Fog(0x24211e, 40, 260);

    // 光照：主光暖白（篝火橙系）+ 环境冷灰青
    const sun = new THREE.DirectionalLight(0xd9c9a8, 2.2);
    sun.position.set(-20, 40, -30);
    this.scene.add(sun);
    const hemi = new THREE.HemisphereLight(0x8a9aa8, 0x2a2320, 0.55);
    this.scene.add(hemi);

    // HUD
    this.telemetryEl = document.createElement('div');
    this.telemetryEl.style.cssText =
      'position:absolute;bottom:52px;left:50%;transform:translateX(-50%);font:bold 24px/1.2 monospace;color:#e8ded2;text-align:center;text-shadow:0 2px 6px rgba(0,0,0,.8);pointer-events:none;z-index:5';
    container.appendChild(this.telemetryEl);
    this.hintEl = document.createElement('div');
    this.hintEl.style.cssText =
      'position:absolute;bottom:18px;left:50%;transform:translateX(-50%);font:13px/1.4 monospace;color:#d4a05a;text-shadow:0 2px 6px rgba(0,0,0,.8);pointer-events:none;z-index:5;white-space:nowrap';
    container.appendChild(this.hintEl);
    this.pipEl = document.createElement('div');
    this.pipEl.style.cssText =
      'position:absolute;top:78px;left:14px;width:230px;height:161px;border:2px solid rgba(232,134,46,.6);border-radius:8px;pointer-events:none;z-index:4;display:none;box-shadow:0 0 12px rgba(0,0,0,.5)';
    container.appendChild(this.pipEl);

    this.buildRoad();
    this.buildSideProps();
    this.buildWeather();
    this.bindInput();
  }

  async start(): Promise<void> {
    await Promise.all([this.loadRV(), this.loadProps()]);
    if (this.disposed) return;
    this.loop();
  }

  // ---- 模型加载 ----
  private async loadRV(): Promise<void> {
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync('/assets/rv/gs_001.glb');
    const rv = gltf.scene;
    // glTF Y-up：车长轴在 Y、车顶在 +Y。绕 X -90° 使车头朝 -Z 前进、车顶仍朝上
    rv.rotation.x = -Math.PI / 2;
    rv.position.y = GROUND_Y;
    rv.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
    this.scene.add(rv);
    this.rv = rv;
  }

  // ---- 道具/丧尸模型加载 ----
  private async loadProps(): Promise<void> {
    const loader = new GLTFLoader();
    // 丧尸动画包
    const z = await loader.loadAsync('/assets/props/zmb.glb');
    const zscene = z.scene;
    zscene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
    this.zombieSource = zscene;
    this.zombieClips = z.animations;
    // 丧尸材质微绿自发光：暗夜中更显眼、更有丧尸感
    zscene.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (!mesh.isMesh) return;
      const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      for (const m of mats) {
        const mat = m as THREE.MeshStandardMaterial;
        if (mat && 'emissive' in mat) {
          mat.emissive = new THREE.Color(0x1f4a2a);
          mat.emissiveIntensity = 0.35;
        }
      }
    });

    // 软路障（可撞飞）：路障/锥桶包
    const b = await loader.loadAsync('/assets/props/barriers.glb');
    b.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.softSources.push(o);
    });

    // 硬路障：军用路障 + 废弃卡车 + 废弃轿车
    const bg = await loader.loadAsync('/assets/props/barricade.glb');
    bg.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
    const t = await loader.loadAsync('/assets/props/wtruck.glb');
    t.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
    const c = await loader.loadAsync('/assets/props/wcar.glb');
    c.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
  }

  // ---- 公路骨架（静态） ----
  private buildRoad(): void {
    // 大地
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(400, 900),
      new THREE.MeshStandardMaterial({ color: 0x191410, roughness: 1 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(0, GROUND_Y - 0.02, -200);
    this.scene.add(ground);

    // 路面
    const road = new THREE.Mesh(
      new THREE.PlaneGeometry(ROAD_HALF * 2, 900),
      new THREE.MeshStandardMaterial({ color: 0x26201a, roughness: 0.95 }),
    );
    road.rotation.x = -Math.PI / 2;
    road.position.set(0, GROUND_Y + 0.01, -200);
    this.scene.add(road);

    // 路肩白线 x2
    for (const sx of [-ROAD_HALF + 0.25, ROAD_HALF - 0.25]) {
      const line = new THREE.Mesh(
        new THREE.PlaneGeometry(0.14, 900),
        new THREE.MeshStandardMaterial({ color: 0x8a7d6d, roughness: 0.9 }),
      );
      line.rotation.x = -Math.PI / 2;
      line.position.set(sx, GROUND_Y + 0.02, -200);
      this.scene.add(line);
    }

    // 中央虚线（可滚动单元）
    const dashMat = new THREE.MeshStandardMaterial({ color: 0x4a3f35, roughness: 0.9 });
    for (let z = -260; z < Z_LOOP; z += 12) {
      const dash = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.06, 3.2), dashMat);
      dash.position.set(0, GROUND_Y + 0.03, z);
      this.scene.add(dash);
      this.dashes.push(dash);
    }
  }

  // ---- 路边元素 + 丧尸池 ----
  private buildSideProps(): void {
    for (let i = 0; i < 26; i++) {
      const side = Math.random() > 0.5 ? 1 : -1;
      const x = side * rng(ROAD_HALF + 2, ROAD_HALF + 34);
      const z = rng(Z_SPAWN, Z_LOOP - 10);
      const g = this.makeProp(x);
      g.position.set(x, GROUND_Y, z);
      this.scene.add(g);
      this.props.push({ group: g, z, speed: 0, kind: 'prop', active: true });
    }
  }

  private makeProp(x: number): THREE.Group {
    const g = new THREE.Group();
    const roll = Math.random();
    if (roll < 0.4) {
      // 枯树：柱 + 分枝
      const trunk = new THREE.Mesh(
        new THREE.CylinderGeometry(0.18, 0.3, 3 + Math.random() * 2, 5),
        new THREE.MeshStandardMaterial({ color: 0x2a2320, roughness: 1 }),
      );
      trunk.position.y = 1.5;
      g.add(trunk);
      const top = new THREE.Mesh(
        new THREE.IcosahedronGeometry(0.7, 1),
        new THREE.MeshStandardMaterial({ color: 0x3d332b, roughness: 1 }),
      );
      top.position.y = 3.4;
      top.scale.set(1, 0.8, 1);
      g.add(top);
    } else if (roll < 0.75) {
      // 废墟：碎 box 堆
      const n = 2 + Math.floor(Math.random() * 3);
      for (let i = 0; i < n; i++) {
        const b = new THREE.Mesh(
          new THREE.BoxGeometry(rng(1, 3), rng(0.6, 1.8), rng(1, 3)),
          new THREE.MeshStandardMaterial({ color: Math.random() > 0.5 ? 0x26201a : 0x3a2f26, roughness: 1 }),
        );
        b.position.set(rng(-1.5, 1.5), rng(0.3, 1.2), rng(-1.5, 1.5));
        b.rotation.y = rng(0, Math.PI);
        g.add(b);
      }
    } else {
      // 路灯：柱 + 灯头（自发光）
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.08, 0.08, 4.2, 6),
        new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 0.8 }),
      );
      pole.position.y = 2.1;
      g.add(pole);
      const arm = new THREE.Mesh(
        new THREE.BoxGeometry(1.6, 0.08, 0.08),
        new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 0.8 }),
      );
      arm.position.set(Math.sign(x) * -0.75, 4.2, 0);
      g.add(arm);
      const lamp = new THREE.Mesh(
        new THREE.SphereGeometry(0.16, 8, 8),
        new THREE.MeshStandardMaterial({ color: 0xe8a04c, emissive: 0xd98e2e, emissiveIntensity: 3 }),
      );
      lamp.position.set(Math.sign(x) * -1.5, 4.2, 0);
      g.add(lamp);
    }
    return g;
  }

  private spawnZombie(): void {
    if (!this.zombieSource) return;
    const side = Math.random() > 0.5 ? 1 : -1;
    const x = side * (Math.random() * 3 + 2);
    const g = this.zombieSource.clone(true);
    g.position.set(x, GROUND_Y, Z_SPAWN);
    const roll = Math.random();
    g.rotation.y = roll > 0.5 ? Math.PI : 0; // 面朝车
    g.scale.setScalar(1.05 + Math.random() * 0.3);
    // 随机挑一个走/跑动画
    const mixer = new THREE.AnimationMixer(g);
    const clip =
      this.zombieClips.find((c) => /walk|run/i.test(c.name)) ?? this.zombieClips[0];
    if (clip) mixer.clipAction(clip).play();
    this.scene.add(g);
    this.props.push({ group: g, z: Z_SPAWN, speed: 1.4 + Math.random() * 1.2, kind: 'zombie', active: true, mixer });
  }

  // ---- 路障生成 ----
  private spawnBlock(): void {
    if (this.hardSources.length === 0 && this.softSources.length === 0) return;
    const roll = Math.random();
    const x = rng(-4, 4);
    if (roll < 0.5 && this.softSources.length > 0) {
      // 软路障：锥桶/矮栏（可撞飞）
      const src = this.softSources[Math.floor(Math.random() * this.softSources.length)];
      const m = src.clone();
      m.rotation.y = Math.random() * Math.PI * 2;
      m.scale.setScalar(0.8 + Math.random() * 0.4);
      m.position.set(x, GROUND_Y, Z_SPAWN);
      this.scene.add(m);
      this.blocks.push({ group: m, z: Z_SPAWN, x, kind: 'soft', active: true, hit: false, flying: false, flyT: 0 });
    } else if (this.hardSources.length > 0) {
      // 硬路障：军用路障/废弃车（横在路中，必须绕或硬撞）
      const src = this.hardSources[Math.floor(Math.random() * this.hardSources.length)];
      const m = src.clone();
      const isVehicle = /Object/.test(src.name);
      m.rotation.y = isVehicle ? Math.PI / 2 + rng(-0.3, 0.3) : rng(-0.2, 0.2);
      m.position.set(x, GROUND_Y, Z_SPAWN);
      this.scene.add(m);
      this.blocks.push({ group: m, z: Z_SPAWN, x, kind: 'hard', active: true, hit: false, flying: false, flyT: 0 });
    }
  }

  // ---- 天气粒子 ----
  private buildWeather(): void {
    // 雨
    const rainN = 500;
    const rp = new Float32Array(rainN * 3);
    for (let i = 0; i < rainN; i++) {
      rp[i * 3] = (Math.random() - 0.5) * 90;
      rp[i * 3 + 1] = Math.random() * 30;
      rp[i * 3 + 2] = Math.random() * -260;
    }
    const rainGeo = new THREE.BufferGeometry();
    rainGeo.setAttribute('position', new THREE.BufferAttribute(rp, 3));
    this.rain = new THREE.Points(
      rainGeo,
      new THREE.PointsMaterial({ color: 0x6a8aaa, size: 0.07, transparent: true, opacity: 0.55 }),
    );
    this.rain.visible = false;
    this.scene.add(this.rain);

    // 雪
    const snowN = 300;
    const sp = new Float32Array(snowN * 3);
    for (let i = 0; i < snowN; i++) {
      sp[i * 3] = (Math.random() - 0.5) * 90;
      sp[i * 3 + 1] = Math.random() * 30;
      sp[i * 3 + 2] = Math.random() * -260;
    }
    const snowGeo = new THREE.BufferGeometry();
    snowGeo.setAttribute('position', new THREE.BufferAttribute(sp, 3));
    this.snow = new THREE.Points(
      snowGeo,
      new THREE.PointsMaterial({ color: 0xe8e8f0, size: 0.14, transparent: true, opacity: 0.7 }),
    );
    this.snow.visible = false;
    this.scene.add(this.snow);
  }

  // ---- 输入 ----
  private bindInput(): void {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
  }

  private onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') this.gasHeld = true;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') this.brakeHeld = true;
    if (e.key === 'q' || e.key === 'Q') this.steerLeft = true;
    if (e.key === 'e' || e.key === 'E') this.steerRight = true;
    if (e.key === '1') this.setCam('chase');
    if (e.key === '2') this.setCam('cockpit');
    if (e.key === '3') this.setCam('rooftop');
  };

  private onKeyUp = (e: KeyboardEvent): void => {
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') this.gasHeld = false;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') this.brakeHeld = false;
    if (e.key === 'q' || e.key === 'Q') this.steerLeft = false;
    if (e.key === 'e' || e.key === 'E') this.steerRight = false;
  };

  private setCam(mode: CamMode): void {
    this.camMode = mode;
  }

  // ---- 主循环 ----
  private loop = (): void => {
    if (this.disposed) return;
    this.raf = requestAnimationFrame(this.loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    this.update(dt);
    this.renderScene(dt);
  };

  private renderScene(dt: number): void {
    const w = this.container.clientWidth || 1280;
    const h = this.container.clientHeight || 720;
    const cam = this.activeCam();

    // 主渲染
    this.renderer.setViewport(0, 0, w, h);
    this.renderer.setScissorTest(false);
    this.renderer.render(this.scene, cam);

    // 车内画中画：仅舱内视角时显示（画面顶部左上）
    if (this.camMode === 'cockpit') {
      const pw = Math.round(Math.min(230, w * 0.3));
      const ph = Math.round(pw * 0.7);
      const px = 14;
      const py = h - 78 - ph; // 顶部 HudBar 之下
      this.camInterior.aspect = pw / ph;
      this.camInterior.updateProjectionMatrix();
      this.renderer.setViewport(px, py, pw, ph);
      this.renderer.setScissor(px, py, pw, ph);
      this.renderer.setScissorTest(true);
      this.renderer.render(this.scene, this.camInterior);
      this.renderer.setScissorTest(false);
      this.renderer.setViewport(0, 0, w, h);
    }
    void dt;
  }

  private activeCam(): THREE.PerspectiveCamera {
    if (this.camMode === 'cockpit') return this.camCockpit;
    if (this.camMode === 'rooftop') return this.camRooftop;
    return this.camChase;
  }

  private update(dt: number): void {
    const state = Game.getState();
    const driving = state.phase === 'driving';

    // 耐久影响极速：耐久越低车越肉
    const maxSpeed = MAX_SPEED * (0.5 + 0.5 * (state.durability / 100));

    // 横向移动（躲避路障）
    const steerSpeed = 7;
    if (this.steerLeft) this.offsetX -= steerSpeed * dt;
    if (this.steerRight) this.offsetX += steerSpeed * dt;
    this.offsetX = Math.max(-4.5, Math.min(4.5, this.offsetX));
    if (this.rv) this.rv.position.x = this.offsetX;

    // 速度物理（天气影响同 2D 版）
    const weather = state.weather;
    let accel = ACCEL;
    let brake = BRAKE;
    if (weather === 'rain') brake = BRAKE * 0.7;
    if (weather === 'snow') accel = ACCEL * 0.6;

    if (driving && this.gasHeld && state.fuel > 0) this.speed += accel * dt;
    else if (this.brakeHeld) this.speed -= brake * dt;
    else this.speed -= DRAG * dt;
    this.speed = Math.max(0, Math.min(maxSpeed, this.speed));

    // 推背感：猛加速→相机后仰下沉+车身前倾（快起慢落）；急刹→反向前顶
    const accelNow = (this.speed - this.prevSpeed) / Math.max(dt, 0.001); // km/h/s
    this.prevSpeed = this.speed;
    if (accelNow > 12) this.boost = Math.min(1, this.boost + dt * 4.5);
    else if (accelNow < -30) this.boost = Math.max(-0.9, this.boost - dt * 4.5);
    else this.boost += (0 - this.boost) * (1 - Math.exp(-dt * 1.1));
    if (this.rv) this.rv.rotation.x = -Math.PI / 2 - this.boost * 0.05;

    const worldSpeed = this.speed * KMH_TO_UNITS;

    // 世界滚动：虚线 + 路边元素
    for (const d of this.dashes) {
      d.position.z += worldSpeed * dt;
      if (d.position.z > Z_LOOP) d.position.z -= 300;
    }
    for (const p of this.props) {
      if (p.kind === 'zombie') {
        p.z += (worldSpeed - p.speed) * dt; // 丧尸朝车走来
        // 朝车的横向位置靠近
        const dx = this.offsetX - p.group.position.x;
        p.group.position.x += Math.sign(dx) * Math.min(Math.abs(dx), worldSpeed * 0.3 * dt);
        if (p.mixer) p.mixer.update(dt);
      } else {
        p.z += worldSpeed * dt;
      }
      p.group.position.z = p.z;
      // 循环回收
      if (p.z > Z_LOOP) {
        if (p.kind === 'zombie') {
          this.scene.remove(p.group);
          p.active = false;
          continue;
        }
        p.z = Z_SPAWN + Math.random() * 60;
        p.group.position.z = p.z;
      }
      // 丧尸撞车（横向接近才算）
      if (p.kind === 'zombie' && p.z > -3.2 && Math.abs(p.group.position.x - this.offsetX) < 1.1) {
        this.scene.remove(p.group);
        p.active = false;
        this.bump(0.45);
        Game.zombieHit();
      }
    }
    this.props = this.props.filter((p) => p.active);

    // 路障滚动 + 碰撞
    for (const b of this.blocks) {
      b.z += worldSpeed * dt;
      b.group.position.z = b.z;
      if (b.flying) {
        // 软路障被撞飞：上抛 + 翻滚
        b.flyT += dt;
        b.group.position.y = GROUND_Y + b.flyT * 3.5;
        b.group.rotation.x += dt * 4;
        b.group.rotation.z += dt * 5;
        if (b.flyT > 0.8) {
          this.scene.remove(b.group);
          b.active = false;
          continue;
        }
      }
      if (!b.hit && b.z > -6.5 && Math.abs(b.group.position.x - this.offsetX) < 2.0) {
        b.hit = true;
        if (b.kind === 'soft') {
          // 软路障：撞飞，轻扣耐久
          Game.damageVehicle(2);
          this.bump(0.35);
          b.flying = true;
          b.flyT = 0;
        } else {
          // 硬路障：重扣耐久 + 强制减速
          Game.damageVehicle(12);
          this.bump(0.85);
          this.speed = Math.max(this.speed * 0.2, 8);
        }
      }
      if (b.z > Z_LOOP && !b.flying) {
        this.scene.remove(b.group);
        b.active = false;
      }
    }
    this.blocks = this.blocks.filter((b) => b.active);

    // 丧尸生成（仅行驶时）
    if (driving && this.speed > 5) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        const rate = 1.5 - (this.speed / MAX_SPEED) * 1.0;
        this.spawnTimer = Math.max(0.4, rate);
        this.spawnZombie();
      }
    }

    // 路障生成（行驶时，约每 3.5-6s 一个）
    if (driving && this.speed > 5) {
      this.blockTimer -= dt;
      if (this.blockTimer <= 0) {
        this.blockTimer = rng(3.5, 6);
        this.spawnBlock();
      }
    }

    // 天气
    this.renderWeather(weather, dt);

    // 里程推进
    if (driving && this.speed > 0) {
      Game.driveTick((this.speed / 3600) * dt);
    }

    // 相机
    this.updateCameras(dt);

    // HUD
    this.updateHud(state.phase === 'driving', state.weather);
  }

  private bump(intensity: number): void {
    this.shakeTime = 0.35;
    this.shakeIntensity = intensity;
  }

  private updateCameras(dt: number): void {
    const cam = this.activeCam();
    const sx = this.offsetX * 0.85;
    // 推背滞后：向后下方压（z 增大、y 降低、看向更近地面），模拟坐车被带一下
    const lz = this.boost * 2.2;
    const ly = -this.boost * 0.55;
    // 追尾：车后上方，看向车头前方
    this.camChase.position.set(sx, 5.2 + ly, 13.5 + lz);
    this.camChase.lookAt(sx * 0.8, 2.2 - this.boost * 1.0, -30 - this.boost * 12);
    // 舱内：驾驶舱内（车头 -Z 端、挡风玻璃后）
    this.camCockpit.position.set(sx * 0.9 + 0.5, 2.3 + ly * 0.4, -3.6 + lz * 0.5);
    this.camCockpit.lookAt(sx * 0.7, 1.6 - this.boost * 0.5, -50 - this.boost * 6);
    // 车顶：车顶上方稍偏后，俯看前方（车顶战斗位）
    this.camRooftop.position.set(sx * 0.9, 6.4 + ly * 0.3, -0.8 + lz * 0.5);
    this.camRooftop.lookAt(sx * 0.7, 4.0 - this.boost * 0.5, -50 - this.boost * 6);
    // 车内画中画机位：驾驶舱中部看向车厢后部
    this.camInterior.position.set(0, 2.4, -2.0);
    this.camInterior.lookAt(0, 2.3, 6);

    // 撞击震屏
    if (this.shakeTime > 0) {
      this.shakeTime -= dt;
      const s = this.shakeIntensity * Math.max(0, this.shakeTime);
      cam.position.x += rng(-s, s) * 0.25;
      cam.position.y += rng(-s, s) * 0.18;
    }

    const w = this.container.clientWidth || 1280;
    const h = this.container.clientHeight || 720;
    if (cam.aspect !== w / h) {
      cam.aspect = w / h;
      cam.updateProjectionMatrix();
    }
    if (this.renderer.domElement.width !== w) {
      this.renderer.setSize(w, h);
    }
  }

  private renderWeather(weather: Weather, dt: number): void {
    // 雾
    if (weather === 'fog') {
      this.scene.fog = new THREE.Fog(0x2a2622, 18, 120);
      this.scene.background = new THREE.Color(0x2a2622);
    } else if (weather === 'rain') {
      this.scene.fog = new THREE.Fog(0x1c2226, 30, 200);
      this.scene.background = new THREE.Color(0x14181c);
    } else if (weather === 'snow') {
      this.scene.fog = new THREE.Fog(0x20242a, 30, 190);
      this.scene.background = new THREE.Color(0x14161a);
    } else {
      this.scene.fog = new THREE.Fog(0x24211e, 40, 260);
      this.scene.background = new THREE.Color(0x1c1a18);
    }

    this.rain.visible = weather === 'rain';
    this.snow.visible = weather === 'snow';
    if (this.rain.visible) this.stepParticles(this.rain, 16 * dt, 0.5);
    if (this.snow.visible) this.stepParticles(this.snow, 3 * dt, 0.15);
    this.weather = weather;
  }

  private stepParticles(points: THREE.Points, fall: number, sway: number): void {
    const pos = points.geometry.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < pos.count; i++) {
      let y = pos.getY(i) - fall;
      if (y < GROUND_Y) y = 30 + Math.random() * 6;
      pos.setY(i, y);
      pos.setX(i, pos.getX(i) + Math.sin(i + performance.now() * 0.0004) * sway * 0.02);
    }
    pos.needsUpdate = true;
  }

  private updateHud(driving: boolean, weather: Weather): void {
    const durability = Game.getState().durability;
    this.telemetryEl.textContent = driving
      ? `${Math.round(this.speed)} km/h · 车况${Math.round(durability)}%`
      : `车况${Math.round(durability)}%`;
    this.hintEl.textContent = `${CAM_HINT[this.camMode]} · ${WEATHER_LABEL[weather]} · 1/2/3 视角，D 油门 A 刹车 Q/E 左右躲避`;
    this.pipEl.style.display = this.camMode === 'cockpit' ? 'block' : 'none';
  }

  dispose(): void {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    this.telemetryEl.remove();
    this.hintEl.remove();
    this.pipEl.remove();
    this.renderer.dispose();
    if (this.renderer.domElement.parentElement === this.container) {
      this.container.removeChild(this.renderer.domElement);
    }
  }
}
