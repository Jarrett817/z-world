import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/examples/jsm/libs/meshopt_decoder.module.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import * as CANNON from 'cannon-es';
import { Game, RoadKind, Weather } from '../core/Game';

const MAX_SPEED = 180; // km/h
const ACCEL = 90; // km/h 每秒
const BRAKE = 150;
const DRAG = 8;
const KMH_TO_UNITS = 0.5; // 驾驶尺度：km/h → 世界单位/秒
const GROUND_Y = -1.56; // 地面高度（glTF Y-up，车底贴地）
const Z_SPAWN = -260; // 世界对象生成/循环重置深度
const Z_LOOP = 40; // 对象越过此 Z 后循环回前方
const ROAD_HALF = 6.5; // 路面半宽

/** 地形起伏：沿 Z 的平缓海拔（米）——末世荒原有明显高低差 */
const groundY = (z: number): number =>
  GROUND_Y + Math.sin(z * 0.06) * 1.0 + Math.sin(z * 0.13 + 2.1) * 0.7 + Math.sin(z * 0.031 + 5) * 0.7;
/** 道路横向弯曲：沿 Z 的路径偏移（米）——山路/废墟弯路 */
const roadX = (z: number): number =>
  Math.sin(z * 0.035) * 4.5 + Math.sin(z * 0.1 + 1.5) * 2.2;
/** 路面段类型：约每 240m 轮换 柏油/土路/水淹 */
const roadTypeAt = (z: number): 'asphalt' | 'dirt' | 'flooded' => {
  const seg = Math.floor(z / 240);
  const r = ((seg % 3) + 3) % 3;
  return r === 0 ? 'asphalt' : r === 1 ? 'dirt' : 'flooded';
};
const ROAD_COLORS: Record<string, number> = {
  asphalt: 0x26201a,
  dirt: 0x4a4030,
  flooded: 0x3a4a42,
};

type CamMode = 'chase' | 'cockpit' | 'rooftop';

const CAM_HINT: Record<CamMode, string> = {
  chase: '追尾视角',
  cockpit: '舱内视角',
  rooftop: '车顶视角',
};

interface SideObj {
  group: THREE.Object3D;
  z: number;
  speed: number; // 仅丧尸使用（相对车的前进速度，m/s）
  kind: 'zombie' | 'prop';
  active: boolean;
  mixer?: THREE.AnimationMixer; // 丧尸动画
  hitDmg?: number; // 丧尸撞击伤害（随天数增强）
  flying?: boolean; // 丧尸被撞飞
  flyT?: number;
  yOff?: number; // 相对地形的固定高度偏移（山/草簇等）
  atkT?: number; // 啃咬攻击计时
  attackClip?: THREE.AnimationAction; // 攻击动画（切换用）
  walkAction?: THREE.AnimationAction; // 走路动画（攻击后恢复）
  attacking?: boolean; // 正在啃咬车（挂在车边）
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

/** 路边遭遇点：补给点 / 废车堆 / 求助者 / 堵路 */
interface RoadEventObj {
  group: THREE.Group;
  z: number;
  x: number;
  kind: RoadKind;
  active: boolean;
  done: boolean; // 已触发过（防重复触发）
  pulse: number; // 指示光脉冲相位
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

  // 主循环/光照
  private dayFactor = 0.5;
  private pendingRoad: RoadEventObj | null = null;

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
  private roadEvents: RoadEventObj[] = [];
  private dashes: THREE.Mesh[] = [];

  // 模型源
  private zombieSource: THREE.Group | null = null;
  private zombieClips: THREE.AnimationClip[] = [];
  private softSources: THREE.Object3D[] = [];
  private hardSources: THREE.Object3D[] = [];
  /** 下载的场景模型源（枯树等） */
  private sceneSources: THREE.Object3D[] = [];
  /** 城市废墟环境（体积大，只作远景天际线） */
  private skylineSource: THREE.Group | null = null;
  /** container 包中的油桶/木箱（路边补给点造型） */
  private supplySources: THREE.Object3D[] = [];

  // 光照（昼夜）
  private sun!: THREE.DirectionalLight;
  private hemi!: THREE.HemisphereLight;
  private headlight!: THREE.SpotLight;
  private headlightL!: THREE.SpotLight;
  private carGlow!: THREE.PointLight;
  private moon!: THREE.Mesh;
  private moonLight!: THREE.DirectionalLight;

  // 天空（太阳/云）
  private sunDisc!: THREE.Mesh;
  private sunGlow!: THREE.Sprite;
  private sunGlow2!: THREE.Sprite;
  private clouds: THREE.Group[] = [];
  private skyDome!: THREE.Mesh;
  private skyUniforms!: { uTop: { value: THREE.Color }; uHor: { value: THREE.Color }; uBot: { value: THREE.Color } };

  // 后期（泛光）
  private composer!: EffectComposer;
  private renderPass!: RenderPass;
  private bloomPass!: UnrealBloomPass;
  private pmrem: THREE.PMREMGenerator | null = null;
  private envTex: THREE.Texture | null = null;

  // 物理（cannon-es）：撞击抛飞动力学
  private physicsWorld!: CANNON.World;
  private flyingBodies: {
    body: CANNON.Body;
    group: THREE.Object3D;
    kind: 'zombie' | 'soft' | 'hard';
    t: number;
    landY: number;
  }[] = [];

  /** 将对象底部对齐到 y=0（解决 GLB 原点不在底导致的浮空/陷地） */
  private groundToZero(obj: THREE.Object3D): void {
    const box = new THREE.Box3().setFromObject(obj);
    const dy = -box.min.y;
    if (Math.abs(dy) > 0.02) obj.position.y += dy;
  }

  /** 撞击损伤速度系数：0.5~1.0，车速越高撞得越狠 */
  private speedFactor(): number {
    return 0.5 + 0.5 * (this.speed / MAX_SPEED);
  }

  // 遭遇/生成节奏
  private roadTimer = 0;
  private nightLamps: THREE.Mesh[] = []; // 路灯灯头（夜晚增强）
  private companionModels: THREE.Group[] = []; // 队友模型（路边求助者）

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
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(this.renderer.domElement);
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';

    this.scene.background = new THREE.Color(0x1c1a18);
    this.scene.fog = new THREE.Fog(0x24211e, 40, 260);

    // 光照：主光暖白（篝火橙系）+ 环境冷灰青；昼夜循环中动态调整
    this.sun = new THREE.DirectionalLight(0xd9c9a8, 2.2);
    this.sun.position.set(-20, 40, -30);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const sc = this.sun.shadow.camera;
    sc.left = -55;
    sc.right = 55;
    sc.top = 55;
    sc.bottom = -55;
    sc.near = 5;
    sc.far = 260;
    this.scene.add(this.sun);
    this.hemi = new THREE.HemisphereLight(0x8a9aa8, 0x2a2320, 0.55);
    this.scene.add(this.hemi);
    // 车头灯（夜晚开启）：双灯更宽更亮，跟随车头朝前方照射
    this.headlight = new THREE.SpotLight(0xffe6b8, 0, 140, Math.PI / 4.5, 0.55, 0.9);
    this.headlight.position.set(-1.0, 2.4, -6);
    this.headlight.target.position.set(-1.0, 1.5, -32);
    this.scene.add(this.headlight);
    this.scene.add(this.headlight.target);
    this.headlightL = new THREE.SpotLight(0xffe6b8, 0, 140, Math.PI / 4.5, 0.55, 0.9);
    this.headlightL.position.set(1.1, 2.4, -6);
    this.headlightL.target.position.set(1.1, 1.5, -32);
    this.scene.add(this.headlightL);
    this.scene.add(this.headlightL.target);
    // 车周补光：夜晚照亮车身周围地面，避免全黑
    this.carGlow = new THREE.PointLight(0xffd9a0, 0, 32, 1.6);
    this.carGlow.position.set(0, 2.6, 0);
    this.scene.add(this.carGlow);
    // 月亮（夜晚可见）与冷白月光
    this.moon = new THREE.Mesh(
      new THREE.SphereGeometry(4.5, 24, 24),
      new THREE.MeshBasicMaterial({ color: 0xdfe8f0 }),
    );
    this.moon.position.set(26, 44, -150);
    this.scene.add(this.moon);
    this.moonLight = new THREE.DirectionalLight(0x8fa8c8, 0);
    this.moonLight.position.set(26, 44, -150);
    this.scene.add(this.moonLight);

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

    // 环境反射（IBL）：渐变天空环境贴图让 PBR 材质有真实反光
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envTex = this.pmrem.fromEquirectangular(this.makeSkyEnvTexture()).texture;
    this.envTex.mapping = THREE.EquirectangularReflectionMapping;
    this.scene.environment = this.envTex;
    this.scene.environmentIntensity = 0.55;

    // 后期：Bloom 泛光（车灯/路灯/太阳真实发光）
    this.composer = new EffectComposer(this.renderer);
    this.renderPass = new RenderPass(this.scene, this.camChase);
    this.composer.addPass(this.renderPass);
    this.bloomPass = new UnrealBloomPass(new THREE.Vector2(w, h), 0.45, 0.7, 0.82);
    this.composer.addPass(this.bloomPass);

    // 物理世界（撞击抛飞动力学）
    this.physicsWorld = new CANNON.World({ gravity: new CANNON.Vec3(0, -24, 0) });
    this.physicsWorld.allowSleep = true;

    this.buildRoad();
    this.buildSkyDome();
    this.buildSky();
    this.buildMountains();
    this.buildGrass();
    this.buildSideProps();
    this.buildWeather();
    this.bindInput();
  }

  async start(): Promise<void> {
    await Promise.all([this.loadRV(), this.loadProps(), this.loadSceneModels(), this.loadCompanions()]);
    if (this.disposed) return;
    this.loop();
  }

  // ---- 模型加载 ----
  private createLoader(): GLTFLoader {
    const l = new GLTFLoader();
    l.setMeshoptDecoder(MeshoptDecoder); // 支持 gltf-transform meshopt 压缩（队友/场景模型）
    return l;
  }

  private async loadRV(): Promise<void> {
    const loader = this.createLoader();
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

  // ---- 队友模型预加载（路边求助者 3D 展示） ----
  private async loadCompanions(): Promise<void> {
    const loader = this.createLoader();
    const paths = [
      '/assets/companions/just_a_girl.glb',
      '/assets/companions/stylized_women.glb',
      '/assets/companions/blonde_bikini.glb',
    ];
    for (const p of paths) {
      try {
        const gltf = await loader.loadAsync(p);
        const m = gltf.scene;
        // 统一缩放到 1.7m 身高（Sketchfab 常以 cm 建模）
        const box = new THREE.Box3().setFromObject(m);
        const h = box.max.y - box.min.y;
        if (h > 0.01) m.scale.setScalar(1.7 / h);
        m.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) {
            o.castShadow = false;
            o.receiveShadow = false;
          }
        });
        this.companionModels.push(m);
      } catch {
        // 单个模型缺失不影响游戏
      }
    }
  }

  // ---- 道具/丧尸模型加载 ----
  private async loadProps(): Promise<void> {
    const loader = this.createLoader();
    // 丧尸动画包（站立低模：Idle/Walk/Attack/Death）
    const z = await loader.loadAsync('/assets/props/zmb_stand.glb');
    const zscene = z.scene;
    // 统一缩放到 1.7m 身高（Sketchfab 常以 cm 建模）
    const zBox = new THREE.Box3().setFromObject(zscene);
    const zH = zBox.max.y - zBox.min.y;
    if (zH > 0.01) zscene.scale.setScalar(1.7 / zH);
    zscene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
    this.zombieSource = zscene;
    this.zombieClips = z.animations;
    // 底部对齐地面（GLB 原点不在底）
    this.groundToZero(zscene);
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
      if ((o as THREE.Mesh).isMesh && o.visible) {
        this.groundToZero(o);
        this.softSources.push(o);
      }
    });

    // 硬路障：军用路障 + 废弃卡车 + 废弃轿车
    const bg = await loader.loadAsync('/assets/props/barricade.glb');
    bg.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) {
        this.groundToZero(o);
        this.hardSources.push(o);
      }
    });
    const t = await loader.loadAsync('/assets/props/wtruck.glb');
    t.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) {
        this.groundToZero(o);
        this.hardSources.push(o);
      }
    });
    const c = await loader.loadAsync('/assets/props/wcar.glb');
    c.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) {
        this.groundToZero(o);
        this.hardSources.push(o);
      }
    });
  }

  /** 加载下载的场景模型（城市废墟作远景/工业杂物作补给点/枯树作路边）；文件未就绪时静默跳过，程序化元素兜底 */
  private async loadSceneModels(): Promise<void> {
    const loader = this.createLoader();
    const paths = [
      '/assets/props/scene_models/building/scene.gltf',
      '/assets/props/scene_models/container/scene.gltf',
      '/assets/props/scene_models/tree/scene.gltf',
    ];
    for (const p of paths) {
      try {
        const gltf = await loader.loadAsync(p);
        const isBuilding = p.includes('/building/');
        const isContainer = p.includes('/container/');
        // 整体底部对齐地面（GLB 原点不在底）
        this.groundToZero(gltf.scene);
        gltf.scene.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) {
            o.castShadow = false;
            o.receiveShadow = false;
            const m = o as THREE.Mesh;
            const mats = Array.isArray(m.material) ? m.material : [m.material];
            for (const mat of mats) {
              const mm = mat as THREE.MeshStandardMaterial;
              if (mm && 'roughness' in mm) mm.roughness = Math.max(mm.roughness, 0.7);
            }
            // container 包：油桶/木箱/金属箱/麻袋 → 补给点造型源
            const name = (o.name ?? '').toLowerCase();
            if (isContainer && /barrel|crate|sack/.test(name) && o.visible) {
              this.supplySources.push(o);
            }
          }
        });
        if (isBuilding) {
          this.skylineSource = gltf.scene;
        } else {
          this.sceneSources.push(gltf.scene);
        }      } catch {
        // 模型尚未就绪：跳过
      }
    }
  }

  // ---- 公路骨架（静态） ----
  private buildRoad(): void {
    const WORLD_LEN = Z_LOOP - Z_SPAWN; // 300

    // 大地（末世枯草，细分顶点跟随地形起伏）
    const groundGeo = new THREE.PlaneGeometry(400, WORLD_LEN, 28, 64);
    const gpos = groundGeo.attributes.position as THREE.BufferAttribute;
    const groundCenterZ = (Z_SPAWN + Z_LOOP) / 2;
    for (let i = 0; i < gpos.count; i++) {
      const wy = gpos.getY(i); // 旋转前几何 Y 即段内坐标
      const wz = groundCenterZ - wy; // rotation.x=-π/2 下 geometry y → world z
      gpos.setY(i, groundY(wz));
    }
    groundGeo.computeVertexNormals();
    const ground = new THREE.Mesh(
      groundGeo,
      new THREE.MeshStandardMaterial({ color: 0x55683e, roughness: 1 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(0, 0, groundCenterZ);
    ground.receiveShadow = true;
    this.scene.add(ground);

    // 路面：按 120m 分段（柏油/土路/水淹），细分跟随起伏与弯道
    for (let segStart = Z_SPAWN; segStart < Z_LOOP; segStart += 120) {
      const segLen = Math.min(120, Z_LOOP - segStart);
      const mid = segStart + segLen / 2;
      const rGeo = new THREE.PlaneGeometry(ROAD_HALF * 2, segLen, 1, 12);
      const rpos = rGeo.attributes.position as THREE.BufferAttribute;
      for (let i = 0; i < rpos.count; i++) {
        const gy = rpos.getY(i); // 段内坐标：-segLen/2..segLen/2
        const worldZ = segStart + segLen / 2 - gy; // rotation.x=-π/2 映射
        rpos.setY(i, groundY(worldZ));
        rpos.setX(i, rpos.getX(i) + roadX(worldZ));
      }
      rGeo.computeVertexNormals();
      const road = new THREE.Mesh(
        rGeo,
        new THREE.MeshStandardMaterial({ color: ROAD_COLORS[roadTypeAt(mid)], roughness: 0.95 }),
      );
      road.rotation.x = -Math.PI / 2;
      road.position.set(0, 0, mid);
      road.receiveShadow = true;
      this.scene.add(road);
    }

    // 路肩白线 x2：拆 30m 段，跟随弯道与起伏
    for (const sx of [-ROAD_HALF + 0.25, ROAD_HALF - 0.25]) {
      for (let z = Z_SPAWN; z < Z_LOOP; z += 30) {
        const len = Math.min(30, Z_LOOP - z);
        const mid = z + len / 2;
        const line = new THREE.Mesh(
          new THREE.PlaneGeometry(0.16, len),
          new THREE.MeshStandardMaterial({ color: 0x8a7d6d, roughness: 0.9 }),
        );
        line.rotation.x = -Math.PI / 2;
        line.position.set(roadX(mid) + sx, groundY(mid) + 0.02, mid);
        this.scene.add(line);
      }
    }

    // 中央虚线（可滚动单元，x 跟随弯道、y 跟随起伏）
    const dashMat = new THREE.MeshStandardMaterial({ color: 0x4a3f35, roughness: 0.9 });
    for (let z = -260; z < Z_LOOP; z += 12) {
      const dash = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.06, 3.2), dashMat);
      dash.position.set(roadX(z), groundY(z) + 0.03, z);
      this.scene.add(dash);
      this.dashes.push(dash);
    }

    // 水域段：路两侧水面（近 z=-160、z=-40 两段）
    for (const wz of [-160, -40]) {
      for (const sx of [-1, 1]) {
        const water = new THREE.Mesh(
          new THREE.PlaneGeometry(90, 120),
          new THREE.MeshStandardMaterial({
            color: 0x2e4a55,
            roughness: 0.25,
            metalness: 0.35,
            transparent: true,
            opacity: 0.85,
          }),
        );
        water.rotation.x = -Math.PI / 2;
        water.position.set(sx * (ROAD_HALF + 45), groundY(wz) - 0.06, wz);
        this.scene.add(water);
      }
    }

    this.buildSkyline();
  }

  /** 远景天际线：城市废墟剪影挂在路两侧远处，随循环滚动 */
  private buildSkyline(): void {
    if (!this.skylineSource) return;
    for (let i = 0; i < 4; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const x = side * rng(48, 70);
      const z = -260 + i * 92;
      const m = this.skylineSource.clone();
      m.scale.setScalar(rng(0.35, 0.55));
      m.rotation.y = rng(0, Math.PI * 2);
      m.position.set(x, GROUND_Y, z);
      this.scene.add(m);
      this.props.push({ group: m, z, speed: 0, kind: 'prop', active: true, yOff: 0 });
    }
  }

  /** 天空：太阳圆盘 + 光晕 + 缓慢漂移的云 */
  private buildSky(): void {
    // 太阳
    this.sunDisc = new THREE.Mesh(
      new THREE.CircleGeometry(7, 32),
      new THREE.MeshBasicMaterial({ color: 0xfff3c2, fog: false }),
    );
    this.sunDisc.position.set(-58, 68, -210);
    this.scene.add(this.sunDisc);
    const glowTex = this.makeGlowTexture();
    this.sunGlow = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map: glowTex,
        color: 0xfff0c0,
        transparent: true,
        opacity: 0.9,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        fog: false,
      }),
    );
    this.sunGlow.scale.set(42, 42, 1);
    this.sunGlow.position.copy(this.sunDisc.position);
    this.scene.add(this.sunGlow);
    // 第二层：更大更淡的外晕
    this.sunGlow2 = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map: glowTex,
        color: 0xffe2a0,
        transparent: true,
        opacity: 0.35,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        fog: false,
      }),
    );
    this.sunGlow2.scale.set(85, 85, 1);
    this.sunGlow2.position.copy(this.sunDisc.position);
    this.scene.add(this.sunGlow2);
    // 云：贴图云 sprite，两层错落漂移
    const cloudTex = this.makeCloudTexture();
    for (let i = 0; i < 6; i++) {
      const far = i >= 3;
      const s = new THREE.Sprite(
        new THREE.SpriteMaterial({
          map: cloudTex,
          color: 0xffffff,
          transparent: true,
          opacity: far ? 0.5 : 0.8,
          depthWrite: false,
        }),
      );
      const w = rng(26, 46) * (far ? 1.4 : 1);
      s.scale.set(w, w * 0.32, 1);
      s.position.set(rng(-95, 95), rng(40, 62), far ? rng(-200, -130) : rng(-120, -55));
      const c = new THREE.Group();
      c.add(s);
      this.scene.add(c);
      this.clouds.push(c);
    }
  }

  /** 渐变天空穹顶：天顶→地平线→地面 三色渐变，昼夜联动（替代纯灰背景） */
  private buildSkyDome(): void {
    this.skyUniforms = {
      uTop: { value: new THREE.Color(0x79a6d2) },
      uHor: { value: new THREE.Color(0xd8cbb0) },
      uBot: { value: new THREE.Color(0x55683e) },
    };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.skyUniforms,
      side: THREE.BackSide,
      depthWrite: false,
      vertexShader: `
        varying vec3 vPos;
        void main() {
          vPos = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform vec3 uTop;
        uniform vec3 uHor;
        uniform vec3 uBot;
        varying vec3 vPos;
        void main() {
          float h = normalize(vPos).y;
          vec3 c = h >= 0.0 ? mix(uHor, uTop, pow(h, 0.55)) : mix(uHor, uBot, pow(-h, 0.45));
          gl_FragColor = vec4(c, 1.0);
        }
      `,
    });
    this.skyDome = new THREE.Mesh(new THREE.SphereGeometry(520, 24, 16), mat);
    this.skyDome.frustumCulled = false;
    this.skyDome.renderOrder = -1; // 最先渲染，避免被近处物体深度遮挡
    this.scene.add(this.skyDome);
  }

  /** 渐变天空环境贴图（equirect）：天顶蓝灰 → 地平线暖沙 → 地面草绿 */
  private makeSkyEnvTexture(): THREE.Texture {
    const cw = 512;
    const ch = 256;
    const cv = document.createElement('canvas');
    cv.width = cw;
    cv.height = ch;
    const ctx = cv.getContext('2d')!;
    const g = ctx.createLinearGradient(0, 0, 0, ch);
    g.addColorStop(0, '#9db4c8');
    g.addColorStop(0.38, '#cfc3a8');
    g.addColorStop(0.52, '#e8d9b8');
    g.addColorStop(0.62, '#7a6b52');
    g.addColorStop(1, '#55683e');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, cw, ch);
    return new THREE.CanvasTexture(cv);
  }

  /** 云朵贴图（sprite）：多团椭圆柔云 */
  private makeCloudTexture(): THREE.Texture {
    const size = 256;
    const cv = document.createElement('canvas');
    cv.width = cv.height = size;
    const ctx = cv.getContext('2d')!;
    ctx.clearRect(0, 0, size, size);
    for (let i = 0; i < 7; i++) {
      const x = size / 2 + (Math.random() - 0.5) * 140;
      const y = size / 2 + (Math.random() - 0.5) * 40;
      const r = 26 + Math.random() * 42;
      const grad = ctx.createRadialGradient(x, y, 0, x, y, r);
      grad.addColorStop(0, 'rgba(255,255,255,0.9)');
      grad.addColorStop(0.6, 'rgba(255,255,255,0.45)');
      grad.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = grad;
      ctx.fillRect(x - r, y - r, r * 2, r * 2);
    }
    return new THREE.CanvasTexture(cv);
  }

  /** 径向渐变光晕贴图 */
  private makeGlowTexture(): THREE.Texture {
    const size = 128;
    const cv = document.createElement('canvas');
    cv.width = cv.height = size;
    const ctx = cv.getContext('2d')!;
    const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    g.addColorStop(0, 'rgba(255,244,200,0.95)');
    g.addColorStop(0.3, 'rgba(255,240,190,0.5)');
    g.addColorStop(1, 'rgba(255,235,180,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, size, size);
    return new THREE.CanvasTexture(cv);
  }

  /** 远景山脉带：两侧灰蓝低多边形山，随世界滚动循环 */
  private buildMountains(): void {
    const mats = [
      new THREE.MeshStandardMaterial({ color: 0x6a6e7a, roughness: 1, flatShading: true }),
      new THREE.MeshStandardMaterial({ color: 0x545968, roughness: 1, flatShading: true }),
      new THREE.MeshStandardMaterial({ color: 0x7a7d86, roughness: 1, flatShading: true }),
    ];
    for (let i = 0; i < 9; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const x = side * rng(58, 112);
      const z = Z_SPAWN + i * 52;
      const h = rng(16, 34);
      const m = new THREE.Mesh(
        new THREE.ConeGeometry(rng(10, 20), h, 6),
        mats[i % mats.length],
      );
      m.position.set(x, groundY(z) + h / 2 - 0.8, z);
      m.rotation.y = rng(0, Math.PI * 2);
      this.scene.add(m);
      this.props.push({ group: m, z, speed: 0, kind: 'prop', active: true, yOff: h / 2 - 0.8 });
    }
  }

  /** 两侧枯草簇（末世草地质感） */
  private buildGrass(): void {
    const mats = [
      new THREE.MeshStandardMaterial({ color: 0x5c6b46, roughness: 1, flatShading: true }),
      new THREE.MeshStandardMaterial({ color: 0x4a5538, roughness: 1, flatShading: true }),
      new THREE.MeshStandardMaterial({ color: 0x6b7a52, roughness: 1, flatShading: true }),
    ];
    for (let i = 0; i < 46; i++) {
      const side = Math.random() > 0.5 ? 1 : -1;
      const x = side * rng(ROAD_HALF + 0.9, ROAD_HALF + 30);
      const z = rng(Z_SPAWN, Z_LOOP - 10);
      const h = rng(0.25, 0.7);
      const m = new THREE.Mesh(
        new THREE.ConeGeometry(rng(0.16, 0.34), h, 5),
        mats[i % mats.length],
      );
      m.position.set(x, groundY(z) + h / 2, z);
      this.scene.add(m);
      this.props.push({ group: m, z, speed: 0, kind: 'prop', active: true, yOff: h / 2 });
    }
  }

  // ---- 路边元素 + 丧尸池 ----
  private buildSideProps(): void {
    for (let i = 0; i < 26; i++) {
      const side = Math.random() > 0.5 ? 1 : -1;
      const x = side * rng(ROAD_HALF + 2, ROAD_HALF + 34);
      const z = rng(Z_SPAWN, Z_LOOP - 10);
      const g = this.makeProp(x);
      g.position.set(x, groundY(z), z);
      this.scene.add(g);
      this.props.push({ group: g, z, speed: 0, kind: 'prop', active: true, yOff: 0 });
    }
  }

  private makeProp(x: number): THREE.Group {
    const g = new THREE.Group();
    // 优先复用下载的场景模型（废弃建筑/集装箱/枯树等）
    if (this.sceneSources.length > 0 && Math.random() < 0.55) {
      const src = this.sceneSources[Math.floor(Math.random() * this.sceneSources.length)];
      const m = src.clone();
      m.scale.setScalar(rng(0.7, 1.5));
      m.rotation.y = rng(0, Math.PI * 2);
      g.add(m);
      return g;
    }
    const roll = Math.random();
    if (roll < 0.3) {
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
    } else if (roll < 0.55) {
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
    } else if (roll < 0.75) {
      // 路灯：柱 + 灯头（自发光，夜晚增强）
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
        new THREE.MeshStandardMaterial({ color: 0xe8a04c, emissive: 0xd98e2e, emissiveIntensity: 0.6 }),
      );
      lamp.position.set(Math.sign(x) * -1.5, 4.2, 0);
      g.add(lamp);
      this.nightLamps.push(lamp);
    } else if (roll < 0.9) {
      // 广告牌：立柱 + 残旧灯箱面板
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.09, 0.12, 3.2, 6),
        new THREE.MeshStandardMaterial({ color: 0x24201c, roughness: 0.9 }),
      );
      pole.position.y = 1.6;
      g.add(pole);
      const panel = new THREE.Mesh(
        new THREE.BoxGeometry(3, 1.9, 0.14),
        new THREE.MeshStandardMaterial({ color: 0x3a2f26, roughness: 1 }),
      );
      panel.position.y = 3.1;
      g.add(panel);
      const glow = new THREE.Mesh(
        new THREE.PlaneGeometry(2.5, 1.4),
        new THREE.MeshStandardMaterial({
          color: 0x8a6a3a,
          emissive: 0x7a4a24,
          emissiveIntensity: 0.5,
          roughness: 0.8,
        }),
      );
      glow.position.set(0, 3.1, Math.sign(x) * 0.08);
      glow.rotation.y = 0;
      g.add(glow);
    } else {
      // 集装箱：锈蚀箱体 + 顶部细节
      const box = new THREE.Mesh(
        new THREE.BoxGeometry(rng(3.5, 4.5), 2.2, 2),
        new THREE.MeshStandardMaterial({ color: Math.random() > 0.5 ? 0x5a4a2e : 0x4a5a6b, roughness: 1 }),
      );
      box.position.y = 1.1;
      g.add(box);
      const rib = new THREE.Mesh(
        new THREE.BoxGeometry(3.5, 0.12, 0.14),
        new THREE.MeshStandardMaterial({ color: 0x3a3026, roughness: 1 }),
      );
      rib.position.y = 0.35;
      g.add(rib);
    }
    return g;
  }

  private spawnZombie(): void {
    if (!this.zombieSource) return;
    // 丧尸随生存天数增强：更快、更大、撞得更疼
    const level = Game.getZombieLevel();
    const side = Math.random() > 0.5 ? 1 : -1;
    const lane = side * (Math.random() * 3 + 2);
    const g = this.zombieSource.clone(true);
    const z = rng(Z_SPAWN, Z_SPAWN + 140); // 生成深度随机，路上错落分布
    g.position.set(roadX(z) + lane, groundY(z), z);
    const roll = Math.random();
    g.rotation.y = roll > 0.5 ? Math.PI : 0; // 面朝车
    g.scale.setScalar((1.05 + Math.random() * 0.3) * (1 + level * 0.04));
    // 随机挑一个走/跑动画
    const mixer = new THREE.AnimationMixer(g);
    const clip =
      this.zombieClips.find((c) => /walk|run/i.test(c.name)) ?? this.zombieClips[0];
    const walkAction = clip ? mixer.clipAction(clip) : undefined;
    if (walkAction) walkAction.play();
    // 攻击动画（新站立模型带 attack/bite；爬行旧包没有则跳过）
    const atkClip = this.zombieClips.find((c) => /attack|hit|bite|swing|slash/i.test(c.name));
    const atkAction = atkClip ? mixer.clipAction(atkClip) : undefined;
    if (atkAction) {
      atkAction.setLoop(THREE.LoopOnce, 1);
      atkAction.clampWhenFinished = true;
    }
    this.scene.add(g);
    this.props.push({
      group: g,
      z,
      speed: (2.2 + Math.random() * 1.6) * (1 + level * 0.15), // 主动走向车（更快、更凶）
      kind: 'zombie',
      active: true,
      mixer,
      hitDmg: 3 + level * 2,
      attackClip: atkAction,
      walkAction,
    });
  }

  // ---- 路边遭遇 ----
  private spawnRoadEvent(): void {
    // 权重：求助者 40%（队友是核心玩法）、补给/废弃车/路障各 20%
    const roll = Math.random();
    const kind: RoadKind = roll < 0.4 ? 'survivor' : roll < 0.6 ? 'supply' : roll < 0.8 ? 'wreck' : 'block';
    const lane = rng(-4.2, 4.2);
    const z = rng(Z_SPAWN, Z_SPAWN + 140); // 生成深度随机，路边遭遇错落分布
    const g = this.buildRoadEventVisual(kind);
    g.position.set(roadX(z) + lane, groundY(z), z);
    this.scene.add(g);
    this.roadEvents.push({ group: g, z, x: lane, kind, active: true, done: false, pulse: Math.random() * 10 });
  }

  private buildRoadEventVisual(kind: RoadKind): THREE.Group {
    const g = new THREE.Group();
    if (kind === 'supply') {
      if (this.supplySources.length > 0) {
        // 用 container 包里的油桶/木箱堆做真实补给点
        const n = 2 + Math.floor(Math.random() * Math.min(3, this.supplySources.length));
        for (let i = 0; i < n; i++) {
          const src = this.supplySources[Math.floor(Math.random() * this.supplySources.length)];
          const m = src.clone();
          m.scale.setScalar(rng(0.9, 1.3));
          m.rotation.y = rng(0, Math.PI * 2);
          m.position.set(rng(-0.9, 0.9), 0, rng(-0.9, 0.9));
          g.add(m);
        }
      } else {
        const box = new THREE.Mesh(
          new THREE.BoxGeometry(1.6, 1.1, 1.6),
          new THREE.MeshStandardMaterial({ color: 0x8a5a2a, roughness: 0.9 }),
        );
        box.position.y = 0.55;
        g.add(box);
        const lid = new THREE.Mesh(
          new THREE.BoxGeometry(1.7, 0.12, 1.7),
          new THREE.MeshStandardMaterial({ color: 0x4a3a2a, roughness: 0.9 }),
        );
        lid.position.y = 1.15;
        g.add(lid);
      }
    } else if (kind === 'wreck' || kind === 'block') {
      const body = new THREE.Mesh(
        new THREE.BoxGeometry(kind === 'block' ? 4.4 : 2.2, 0.85, kind === 'block' ? 2.0 : 4.2),
        new THREE.MeshStandardMaterial({ color: 0x3a3128, roughness: 1 }),
      );
      body.position.y = 0.55;
      body.rotation.y = kind === 'block' ? 0 : rng(0, Math.PI);
      g.add(body);
      for (let i = 0; i < 4; i++) {
        const w = new THREE.Mesh(
          new THREE.CylinderGeometry(0.36, 0.36, 0.3, 10),
          new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 1 }),
        );
        w.rotation.x = Math.PI / 2;
        w.position.set((i % 2 === 0 ? 1 : -1) * (kind === 'block' ? 1.4 : 0.8), 0.36, i < 2 ? 0.9 : -0.9);
        g.add(w);
      }
    } else {
      // 求助者：优先用真实队友模型，缺失时人形剪影占位
      const cm = this.companionModels.length > 0 ? this.companionModels[Math.floor(Math.random() * this.companionModels.length)] : null;
      if (cm) {
        const p = cm.clone(true);
        p.position.y = 0;
        p.rotation.y = rng(0, Math.PI * 2);
        g.add(p);
      } else {
        const body = new THREE.Mesh(
          new THREE.CapsuleGeometry(0.26, 0.7, 4, 8),
          new THREE.MeshStandardMaterial({ color: 0x4a3f35, roughness: 1 }),
        );
        body.position.y = 0.85;
        g.add(body);
        const head = new THREE.Mesh(
          new THREE.SphereGeometry(0.2, 10, 8),
          new THREE.MeshStandardMaterial({ color: 0x6b5848, roughness: 1 }),
        );
        head.position.y = 1.62;
        g.add(head);
      }
    }
    // 底部光环 + 竖直光柱（脉冲指示）
    const glowMat = new THREE.MeshStandardMaterial({
      color: 0xffb45e,
      emissive: 0xff8a2e,
      emissiveIntensity: 1.6,
      transparent: true,
      opacity: 0.85,
    });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1.1, 0.06, 6, 24), glowMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.08;
    g.add(ring);
    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(0.1, 0.1, 5, 6, 1, true),
      glowMat.clone(),
    );
    const beamMat = beam.material as THREE.MeshStandardMaterial;
    beamMat.opacity = 0.3;
    beamMat.depthWrite = false;
    beam.position.y = 2.6;
    g.add(beam);
    return g;
  }

  private roadHint(kind: RoadKind): string {
    switch (kind) {
      case 'supply':
        return '路边补给点！空格停车搜刮';
      case 'wreck':
        return '废弃车堆！空格停车处理';
      case 'survivor':
        return '有人求救！空格停车搭救';
      case 'block':
        return '道路被堵！空格停车处理';
    }
  }

  // ---- 路障生成 ----
  private spawnBlock(): void {
    if (this.hardSources.length === 0 && this.softSources.length === 0) return;
    const roll = Math.random();
    const lane = rng(-4, 4);
    const z = rng(Z_SPAWN, Z_SPAWN + 140); // 生成深度随机，路障错落分布
    if (roll < 0.5 && this.softSources.length > 0) {
      // 软路障：锥桶/矮栏（可撞飞）
      const src = this.softSources[Math.floor(Math.random() * this.softSources.length)];
      const m = src.clone();
      m.rotation.y = Math.random() * Math.PI * 2;
      m.scale.setScalar(0.8 + Math.random() * 0.4);
      m.position.set(roadX(z) + lane, groundY(z), z);
      this.scene.add(m);
      this.blocks.push({ group: m, z, x: lane, kind: 'soft', active: true, hit: false, flying: false, flyT: 0 });
    } else if (this.hardSources.length > 0) {
      // 硬路障：军用路障/废弃车（横在路中，必须绕或硬撞）
      const src = this.hardSources[Math.floor(Math.random() * this.hardSources.length)];
      const m = src.clone();
      const isVehicle = /Object/.test(src.name);
      m.rotation.y = isVehicle ? Math.PI / 2 + rng(-0.3, 0.3) : rng(-0.2, 0.2);
      m.position.set(roadX(z) + lane, groundY(z), z);
      this.scene.add(m);
      this.blocks.push({ group: m, z, x: lane, kind: 'hard', active: true, hit: false, flying: false, flyT: 0 });
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
    if (e.key === 'p' || e.key === 'P') Game.togglePark();
    if (e.key === ' ') {
      e.preventDefault();
      if (this.pendingRoad) {
        const k = this.pendingRoad.kind;
        this.pendingRoad = null;
        Game.openRoadEvent(k);
      }
    }
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
    this.renderPass.camera = cam;

    // 主渲染（Bloom 泛光后期）
    this.composer.render();

    // 车内画中画：仅舱内视角时显示（画面顶部左上，直渲无泛光）
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

    // 游戏时钟推进（驾驶与事件阶段都走时间）
    if (driving || state.phase === 'event') {
      Game.advanceClock(dt);
    }

    // 耐久影响极速：耐久越低车越肉
    const maxSpeed = MAX_SPEED * (0.5 + 0.5 * (state.durability / 100));

    // 横向移动（躲避路障）
    const steerSpeed = 7;
    if (this.steerLeft) this.offsetX -= steerSpeed * dt;
    if (this.steerRight) this.offsetX += steerSpeed * dt;
    this.offsetX = Math.max(-4.5, Math.min(4.5, this.offsetX));
    if (this.rv) {
      this.rv.position.x = this.offsetX + roadX(0);
      this.rv.position.y = groundY(0) + 0.05;
    }

    // 速度物理（天气影响同 2D 版）
    const weather = state.weather;
    let accel = ACCEL;
    let brake = BRAKE;
    if (weather === 'rain') brake = BRAKE * 0.7;
    if (weather === 'snow') accel = ACCEL * 0.6;

    const parked = state.parked && driving;
    if (parked) {
      // 停车：快速刹停
      this.speed = Math.max(0, this.speed - brake * 2.5 * dt);
    } else if (driving && this.gasHeld && state.fuel > 0) {
      this.speed += accel * dt;
    } else if (this.brakeHeld) {
      this.speed -= brake * dt;
    } else {
      this.speed -= DRAG * dt;
    }
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
    // 云缓慢漂移
    for (const c of this.clouds) {
      c.position.x += dt * 0.8;
      if (c.position.x > 120) c.position.x = -120;
    }
    for (const d of this.dashes) {
      d.position.z += worldSpeed * dt;
      if (d.position.z > Z_LOOP) d.position.z -= 300;
      d.position.x = roadX(d.position.z);
      d.position.y = groundY(d.position.z) + 0.03;
    }
    for (const p of this.props) {
      if (p.kind === 'zombie') {
        const targetX = this.offsetX + roadX(0);
        const dx = targetX - p.group.position.x;
        // 贴近车头：挂在车边啃咬（持续扣耐久；不主动撞飞，直到被玩家碾压）
        const close = !p.flying && p.z > -10.5 && Math.abs(p.group.position.x - targetX) < 1.4;
        if (close) {
          p.attacking = true;
          p.z = -9; // 挂车边不随世界滚动
          p.group.position.x = targetX + (p.group.position.x > targetX ? 1.0 : -1.0);
          p.atkT = (p.atkT ?? 0) + dt;
          if (p.atkT > 0.8) {
            p.atkT = 0;
            Game.damageVehicle(1);
            this.bump(0.18);
            if (p.attackClip) {
              p.walkAction?.stop();
              p.attackClip.reset().play(); // 播一次攻击
            }
          }
        } else {
          p.attacking = false;
          p.z += (worldSpeed - p.speed) * dt; // 世界滚动 + 丧尸主动走向车
          p.group.position.x += Math.sign(dx) * Math.min(Math.abs(dx), worldSpeed * 0.35 * dt);
        }
        if (p.mixer) {
          // 攻击播完自动恢复走路
          if (p.attackClip && !p.attackClip.isRunning() && p.walkAction && !p.walkAction.isRunning()) {
            p.walkAction.play();
          }
          p.mixer.update(dt);
        }
      } else {
        p.z += worldSpeed * dt;
      }
      p.group.position.z = p.z;
      // 丧尸被撞飞：物理引擎接管位置（见 launch）
      if (p.kind === 'zombie' && p.flying) {
        if (p.mixer) p.mixer.stopAllAction();
        continue;
      }
      p.group.position.y = groundY(p.z) + (p.yOff ?? 0);
      // 循环回收
      if (p.z > Z_LOOP) {
        if (p.kind === 'zombie') {
          this.scene.remove(p.group);
          p.active = false;
          continue;
        }
        p.z = Z_SPAWN + Math.random() * 60;
        p.group.position.z = p.z;
        p.group.position.y = groundY(p.z) + (p.yOff ?? 0);
      }
      // 丧尸撞车（横向接近才算）：按车速扣耐久 + 物理撞飞
      if (
        p.kind === 'zombie' &&
        !p.flying &&
        p.z > -9.8 &&
        Math.abs(p.group.position.x - (this.offsetX + roadX(0))) < 1.1
      ) {
        this.bump(0.45);
        Game.zombieHit(Math.round((p.hitDmg ?? 3) * this.speedFactor() * 0.5));
        p.flying = true;
        this.launch(p.group, 'zombie');
        p.active = false;
      }
    }
    this.props = this.props.filter((p) => p.active);

    // 路障滚动 + 碰撞
    for (const b of this.blocks) {
      b.z += worldSpeed * dt;
      b.group.position.z = b.z;
      if (b.flying) {
        // 被撞飞：物理引擎接管位置
        continue;
      }
      b.group.position.x = roadX(b.z) + b.x;
      b.group.position.y = groundY(b.z);
      if (!b.hit && b.z > -6.5 && Math.abs(b.group.position.x - (this.offsetX + roadX(0))) < 2.0) {
        b.hit = true;
        const sf = this.speedFactor();
        if (b.kind === 'soft') {
          // 软路障：撞飞，轻扣耐久（随车速）
          Game.damageVehicle(Math.round(1.5 * sf));
          this.bump(0.35);
          b.flying = true;
          this.launch(b.group, 'soft');
          b.active = false;
        } else {
          // 硬路障：重扣耐久（随车速）+ 强制减速 + 物理弹开
          Game.damageVehicle(Math.round(7 * sf));
          this.bump(0.85);
          this.speed = Math.max(this.speed * 0.25, 8);
          b.flying = true;
          this.launch(b.group, 'hard');
          b.active = false;
        }
      }
      if (b.z > Z_LOOP && !b.flying) {
        this.scene.remove(b.group);
        b.active = false;
      }
    }
    this.blocks = this.blocks.filter((b) => b.active);

    // 路边遭遇：滚动 + 接近提示（按空格触发）
    for (const re of this.roadEvents) {
      re.z += worldSpeed * dt;
      re.group.position.z = re.z;
      re.group.position.x = roadX(re.z) + re.x;
      re.group.position.y = groundY(re.z);
      re.pulse += dt;
      // 光环脉冲
      const ring = re.group.children.find(
        (c) => (c as THREE.Mesh).isMesh && (c as THREE.Mesh).geometry.type === 'TorusGeometry',
      ) as THREE.Mesh | undefined;
      if (ring) {
        const m = ring.material as THREE.MeshStandardMaterial;
        if (m) m.emissiveIntensity = 1.2 + Math.sin(re.pulse * 3) * 0.8;
      }
      if (re.z > Z_LOOP) {
        this.scene.remove(re.group);
        re.active = false;
        continue;
      }
      if (!re.done && re.z > -9 && re.z < 3 && Math.abs(re.group.position.x - (this.offsetX + roadX(0))) < 3.4) {
        re.done = true;
        this.pendingRoad = re;
      }
    }
    this.roadEvents = this.roadEvents.filter((r) => r.active);

    // 物理：撞击抛飞刚体步进 + 同步 Three 位置（抛物线/翻滚/落地消失）
    this.physicsWorld.step(1 / 60, Math.min(dt, 0.033), 3);
    for (let i = this.flyingBodies.length - 1; i >= 0; i--) {
      const fb = this.flyingBodies[i];
      fb.t += dt;
      const q = fb.body.quaternion;
      fb.group.position.set(fb.body.position.x, fb.body.position.y, fb.body.position.z);
      fb.group.quaternion.set(q.x, q.y, q.z, q.w);
      if (fb.body.position.y <= fb.landY + 0.08 && fb.t > 0.35) {
        this.scene.remove(fb.group);
        this.physicsWorld.removeBody(fb.body);
        this.flyingBodies.splice(i, 1);
      }
    }

    // 丧尸生成（仅行驶时）
    if (driving && !parked && this.speed > 5) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        const rate = 1.5 - (this.speed / MAX_SPEED) * 1.0;
        this.spawnTimer = Math.max(0.4, rate);
        this.spawnZombie();
      }
    }

    // 路障生成（行驶时，约每 3.5-6s 一个）
    if (driving && !parked && this.speed > 5) {
      this.blockTimer -= dt;
      if (this.blockTimer <= 0) {
        this.blockTimer = rng(3.5, 6);
        this.spawnBlock();
      }
    }

    // 路边遭遇生成（行驶时，约每 10-18s 一个，最多同时 3 个）
    if (driving && !parked && this.speed > 8) {
      this.roadTimer -= dt;
      if (this.roadTimer <= 0) {
        this.roadTimer = rng(10, 18);
        if (this.roadEvents.length < 3) this.spawnRoadEvent();
      }
    }

    // 昼夜光照
    this.updateLighting(state.hour, state.weather);

    // 天气
    this.renderWeather(weather, dt, this.dayFactor);

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

  /** 撞击抛飞：创建 cannon 刚体施加冲量，flyingBodies 每帧同步回 Three */
  private launch(group: THREE.Object3D, kind: 'zombie' | 'soft' | 'hard'): void {
    const shape =
      kind === 'zombie'
        ? new CANNON.Sphere(0.6)
        : kind === 'soft'
          ? new CANNON.Box(new CANNON.Vec3(1.1, 0.6, 0.9))
          : new CANNON.Box(new CANNON.Vec3(2.2, 1.1, 1.3));
    const body = new CANNON.Body({
      mass: kind === 'zombie' ? 70 : kind === 'soft' ? 15 : 500,
      shape,
    });
    const gy = groundY(group.position.z);
    body.position.set(group.position.x, Math.max(group.position.y, gy) + 1.2, group.position.z);
    const vz = Math.max(this.speed * KMH_TO_UNITS, 8);
    body.velocity.set(
      (Math.random() - 0.5) * 6,
      6.5 + Math.random() * 3.5,
      vz * (kind === 'zombie' ? 0.95 : kind === 'soft' ? 0.8 : 0.5),
    );
    body.angularVelocity.set((Math.random() - 0.5) * 10, (Math.random() - 0.5) * 8, (Math.random() - 0.5) * 10);
    body.linearDamping = 0.12;
    body.angularDamping = 0.25;
    this.physicsWorld.addBody(body);
    this.flyingBodies.push({ body, group, kind, t: 0, landY: gy });
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
      this.composer.setSize(w, h);
    }
  }

  private renderWeather(weather: Weather, dt: number, dayFactor: number): void {
    // 天气基调 + 昼夜调制背景与雾（白天基调够亮，夜晚经 lerp 变暗）
    let base: THREE.Color;
    let fogNear = 70;
    let fogFar = 420;
    if (weather === 'fog') {
      base = new THREE.Color(0x7a828c);
      fogNear = 24;
      fogFar = 150;
    } else if (weather === 'rain') {
      base = new THREE.Color(0x56606a);
      fogNear = 40;
      fogFar = 220;
    } else if (weather === 'snow') {
      base = new THREE.Color(0x5e6a78);
      fogNear = 40;
      fogFar = 210;
    } else {
      base = new THREE.Color(0xb0c4d8);
      fogFar = 720;
    }
    const nightMix = Math.max(0, 1 - dayFactor);
    const tint = base.clone().lerp(new THREE.Color(0x171b22), nightMix * 0.6);
    this.scene.background = tint;
    this.scene.fog = new THREE.Fog(tint, fogNear, fogFar);

    this.rain.visible = weather === 'rain';
    this.snow.visible = weather === 'snow';
    if (this.rain.visible) this.stepParticles(this.rain, 16 * dt, 0.5);
    if (this.snow.visible) this.stepParticles(this.snow, 3 * dt, 0.15);
    this.weather = weather;
  }

  /** 昼夜光照：阳光色温/强度、环境光、车头灯、路灯随游戏小时变化 */
  private updateLighting(hour: number, weather: Weather): void {
    let dayFactor = 0;
    if (hour >= 5 && hour <= 20) {
      dayFactor = Math.sin(((hour - 5) / 15) * Math.PI);
    }
    dayFactor = Math.max(0.12, dayFactor);
    this.dayFactor = dayFactor;

    // 阳光色温：清晨/黄昏偏橙，正午偏白
    const t = Math.abs(hour - 12) / 12;
    const sunColor = new THREE.Color(1.0, 0.94 - t * 0.28, 0.82 - t * 0.42);
    // 雨雪天阳光打折扣
    const dim = weather === 'rain' || weather === 'snow' ? 0.6 : 1;
    this.sun.color.copy(sunColor);
    this.sun.intensity = dayFactor * 2.2 * dim;
    this.sun.position.set(-20, 40, -30);
    // 阴影白天开、夜晚关（省性能）
    this.sun.castShadow = dayFactor > 0.25;

    // 环境光：夜晚抬升最低亮度，避免全黑；白天随日升
    const nightOn = hour < 5 || hour >= 20 || dayFactor < 0.35;
    this.hemi.intensity = nightOn ? 0.3 : 0.15 + dayFactor * 0.4;
    this.hemi.color.setHSL(0.58, 0.2, nightOn ? 0.5 : 0.42 + dayFactor * 0.18);

    // IBL 环境反射：白天强、夜晚弱（PBR 反光随天色）
    this.scene.environmentIntensity = nightOn ? 0.12 : 0.25 + dayFactor * 0.3;

    // 泛光：白天克制（几乎不用，避免光晕糊天顶），夜晚强（车灯/路灯发光）
    this.bloomPass.strength = nightOn ? 0.65 : 0.18;
    // 曝光：白天提亮通透，夜晚回落
    this.renderer.toneMappingExposure = 1.08 + dayFactor * 0.5;

    // 车头灯双灯：夜晚开启，跟随车身横向偏移
    const hx = this.offsetX * 0.9;
    this.headlight.intensity = nightOn ? 34 : 0;
    this.headlight.position.x = hx - 1.0;
    this.headlight.target.position.x = hx - 1.0;
    this.headlightL.intensity = nightOn ? 34 : 0;
    this.headlightL.position.x = hx + 1.1;
    this.headlightL.target.position.x = hx + 1.1;

    // 车周补光：夜晚点亮车身周围
    this.carGlow.intensity = nightOn ? 7 : 0;
    this.carGlow.position.x = hx;

    // 月亮与月光：夜晚可见，冷白月光补足夜色
    this.moon.visible = nightOn;
    this.moonLight.intensity = nightOn ? 0.4 : 0;

    // 太阳/云：白天可见，黄昏渐隐
    const sunVis = Math.max(0, dayFactor - 0.06);
    this.sunDisc.visible = sunVis > 0;
    this.sunGlow.visible = sunVis > 0;
    this.sunGlow.material.opacity = 0.6 * sunVis;
    this.sunGlow2.visible = sunVis > 0;
    this.sunGlow2.material.opacity = 0.2 * sunVis;
    for (const c of this.clouds) {
      const s = c.children[0] as THREE.Sprite;
      if (s && (s.material as THREE.SpriteMaterial)) {
        (s.material as THREE.SpriteMaterial).opacity =
          0.18 + 0.68 * dayFactor;
      }
    }

    // 路灯灯头：夜晚增强
    for (const lamp of this.nightLamps) {
      const m = lamp.material as THREE.MeshStandardMaterial;
      if (m) m.emissiveIntensity = nightOn ? 4 : 0.35;
    }

    // 渐变天空穹顶：白/黄昏/夜 三套配色，按 dayFactor 与时刻过渡
    const dusk = Math.abs(hour - 18.5) < 2.5 || Math.abs(hour - 6) < 1.5;
    const u = this.skyUniforms;
    const topDay = new THREE.Color(0xa8d8f4);
    const horDay = new THREE.Color(0xf6f0d8);
    const botDay = new THREE.Color(0x6a7d4a);
    const topDusk = new THREE.Color(0x5a6b8a);
    const horDusk = new THREE.Color(0xe0a060);
    const botDusk = new THREE.Color(0x46362a);
    const topNight = new THREE.Color(0x0b1020);
    const horNight = new THREE.Color(0x2c3548);
    const botNight = new THREE.Color(0x0a0d14);
    let mixD = dusk ? 1 : 0;
    if (dusk) {
      // 黄昏随时间渐变回昼夜
      const h6 = Math.abs(hour - 6);
      const h18 = Math.abs(hour - 18.5);
      const near = Math.min(h6, h18);
      mixD = Math.max(0, 1 - (near - 0.5) / 2);
    }
    const n = 1 - dayFactor; // 夜晚系数
    u.uTop.value.copy(topDay).lerp(topDusk, mixD * (1 - n * 0.7)).lerp(topNight, n);
    u.uHor.value.copy(horDay).lerp(horDusk, mixD * (1 - n * 0.7)).lerp(horNight, n);
    u.uBot.value.copy(botDay).lerp(botDusk, mixD * (1 - n * 0.7)).lerp(botNight, n);
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
    const s = Game.getState();
    const hh = Math.floor(s.hour);
    const mm = Math.floor((s.hour - hh) * 60);
    const time = `D${s.day} ${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    this.telemetryEl.textContent = driving
      ? `${Math.round(this.speed)} km/h · 车况${Math.round(s.durability)}% · ${time}`
      : `车况${Math.round(s.durability)}% · ${time}`;

    let hint = `${CAM_HINT[this.camMode]} · ${WEATHER_LABEL[weather]} · D 油门 A 刹车 Q/E 躲避 1/2/3 视角`;
    if (s.parked) hint += ' · P 继续行驶';
    else hint += ' · P 停车';
    if (this.pendingRoad) {
      hint = `【${this.roadHint(this.pendingRoad.kind)}】`;
    }
    this.hintEl.textContent = hint;
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
    this.composer.dispose();
    this.pmrem?.dispose();
    this.envTex?.dispose();
    for (const fb of this.flyingBodies) {
      this.physicsWorld.removeBody(fb.body);
    }
    this.flyingBodies = [];
    this.renderer.dispose();
    if (this.renderer.domElement.parentElement === this.container) {
      this.container.removeChild(this.renderer.domElement);
    }
  }
}
