'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');
const {
  W,
  H,
  TICK_RATE,
  SNAPSHOT_RATE,
  DT,
  ROOM_COUNTDOWN_SECONDS,
  PLAYER_W,
  PLAYER_H,
  PLAYER_Y,
  POWERUP_CHANCE,
  HOLD_FIRE_INTERVAL,
  BRICK_COLS,
  BRICK_ROWS,
  BRICK_W,
  BRICK_H,
  BRICK_GAP,
  BRICK_X0,
  WALL_Y,
  WEAPONS,
  WEAPON_ORDER,
  POWER_KINDS,
  ACTION_KINDS,
  ROOM_CODE_ALPHABET,
  ROOM_CODE_LENGTH,
  cleanInt,
  cloneDefaultRules,
  sanitizeRules,
  roomWeapon
} = require('./src/rules');

const PORT = Number(process.env.PORT || 8787);
const STATIC_ROOT = process.env.STATIC_ROOT || path.join(__dirname, '..', 'web_export');
const HTTPS_KEY = process.env.HTTPS_KEY || process.env.SSL_KEY_PATH || '';
const HTTPS_CERT = process.env.HTTPS_CERT || process.env.SSL_CERT_PATH || '';
const HTTPS_CA = process.env.HTTPS_CA || process.env.SSL_CA_PATH || '';
const HTTPS_ENABLED = HTTPS_KEY !== '' && HTTPS_CERT !== '';
const REDIRECT_HTTP_PORT = Number(process.env.REDIRECT_HTTP_PORT || 0);

let nextRoomId = 1000;
let nextObjectId = 1;
const rooms = new Map();
const roomCodes = new Map();

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function shuffleArray(values) {
  const output = values.slice();
  for (let i = output.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [output[i], output[j]] = [output[j], output[i]];
  }
  return output;
}

function normalizeRoomCode(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
}

function generateRoomCode() {
  for (let attempt = 0; attempt < 1000; attempt++) {
    let code = '';
    for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
      code += ROOM_CODE_ALPHABET[Math.floor(Math.random() * ROOM_CODE_ALPHABET.length)];
    }
    if (!roomCodes.has(code)) return code;
  }
  return String(nextRoomId + Math.floor(Math.random() * 100000));
}

function invitePathFor(room) {
  return `/?room=${encodeURIComponent(room.code)}`;
}

function distanceSquared(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return dx * dx + dy * dy;
}

function circleRectCollides(cx, cy, r, rect) {
  const closestX = clamp(cx, rect.x, rect.x + rect.w);
  const closestY = clamp(cy, rect.y, rect.y + rect.h);
  const dx = cx - closestX;
  const dy = cy - closestY;
  return dx * dx + dy * dy <= r * r;
}

function segmentCircleCollision(x1, y1, x2, y2, cx, cy, r) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const len2 = dx * dx + dy * dy;
  if (len2 <= 0.0001) {
    const sx = cx - x2;
    const sy = cy - y2;
    return sx * sx + sy * sy <= r * r ? { x: x2, y: y2, t: 1 } : null;
  }
  const t = clamp(((cx - x1) * dx + (cy - y1) * dy) / len2, 0, 1);
  const px = x1 + dx * t;
  const py = y1 + dy * t;
  const ddx = cx - px;
  const ddy = cy - py;
  if (ddx * ddx + ddy * ddy > r * r) return null;
  return { x: px, y: py, t };
}

function normalizeBall(ball, room = null) {
  const ballRules = room && room.rules ? room.rules.ball : cloneDefaultRules().ball;
  const speed = Math.hypot(ball.vx, ball.vy);
  if (speed <= 0.0001) return;
  let target = speed;
  if (speed < ballRules.minSpeed) target = ballRules.minSpeed;
  if (speed > ballRules.maxSpeed) target = ballRules.maxSpeed;
  if (target !== speed) {
    const k = target / speed;
    ball.vx *= k;
    ball.vy *= k;
  }
}

function safeSend(ws, data) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

function createAmmoReserve(rules) {
  const reserve = {};
  const weapons = rules && rules.weapons ? rules.weapons : WEAPONS;
  for (const weapon of WEAPON_ORDER) reserve[weapon] = weapons[weapon].ammo;
  return reserve;
}

function createAmmoReloadAt() {
  const reloadAt = {};
  for (const weapon of WEAPON_ORDER) reloadAt[weapon] = 0;
  return reloadAt;
}

function createPlayer(role, name = 'Player', rules = cloneDefaultRules()) {
  const ammoReserve = createAmmoReserve(rules);
  const ammoReloadAt = createAmmoReloadAt();
  return {
    role,
    name,
    x: W * 0.5,
    y: PLAYER_Y[role],
    move: 0,
    targetX: null,
    fire: false,
    fireDown: false,
    firePressed: false,
    holdRepeatAt: 0,
    queuedSwitch: '',
    active: 'sniper',
    ammoReserve,
    ammoReloadAt,
    ammo: ammoReserve.sniper,
    nextShotAt: 0,
    protectedUntil: 0,
    rapidUntil: 0,
    splitUntil: 0,
    actionStacks: Object.fromEntries(ACTION_KINDS.map((kind) => [kind, 0])),
    aiNextFireAt: 0,
    aiDecisionAt: 0
  };
}

function createPowerupBag(rules = cloneDefaultRules()) {
  const brickCount = BRICK_COLS * BRICK_ROWS;
  const powerupCount = cleanInt(brickCount * (rules.powerups ? rules.powerups.chance : POWERUP_CHANCE), 0, 0, brickCount);
  const bag = [];
  for (let i = 0; i < powerupCount; i++) {
    bag.push(POWER_KINDS[i % POWER_KINDS.length]);
  }
  return shuffleArray(bag);
}

function createBricks(rules = cloneDefaultRules()) {
  const bricks = [];
  const basePowerups = createPowerupBag(rules);
  for (const owner of [1, 0]) {
    const startY = WALL_Y[owner];
    const positions = shuffleArray(Array.from({ length: BRICK_COLS * BRICK_ROWS }, (_, i) => i));
    const assignedPowerups = new Map();
    for (let i = 0; i < basePowerups.length; i++) assignedPowerups.set(positions[i], basePowerups[i]);
    for (let row = 0; row < BRICK_ROWS; row++) {
      for (let col = 0; col < BRICK_COLS; col++) {
        const index = row * BRICK_COLS + col;
        bricks.push({
          id: nextObjectId++,
          owner,
          x: BRICK_X0 + col * (BRICK_W + BRICK_GAP),
          y: startY + row * (BRICK_H + BRICK_GAP),
          w: BRICK_W,
          h: BRICK_H,
          alive: true,
          powerupKind: assignedPowerups.get(index) || ''
        });
      }
    }
  }
  return bricks;
}

function createBall(rules = cloneDefaultRules()) {
  const ballRules = rules.ball || cloneDefaultRules().ball;
  return {
    id: nextObjectId++,
    x: W * 0.5,
    y: H * 0.5,
    vx: 0,
    vy: 0,
    r: ballRules.radius
  };
}

function createRoom(options = {}) {
  const id = String(nextRoomId++);
  const rules = sanitizeRules(options.rules || {});
  const requestedCode = normalizeRoomCode(options.code);
  const code = requestedCode && !roomCodes.has(requestedCode) ? requestedCode : generateRoomCode();
  const room = {
    id,
    code,
    public: Boolean(options.public),
    hostRole: null,
    rules,
    clients: [null, null],
    botRole: null,
    players: [createPlayer(0, 'Player 1', rules), createPlayer(1, 'Player 2', rules)],
    status: 'waiting',
    winner: -1,
    countdownRemaining: 0,
    time: 0,
    balls: [createBall(rules)],
    bricks: createBricks(rules),
    projectiles: [],
    powerups: [],
    events: []
  };
  rooms.set(id, room);
  roomCodes.set(code, id);
  return room;
}

function connectedCount(room) {
  return room.clients.reduce((count, ws) => count + (ws ? 1 : 0), 0) + (room.botRole === 0 || room.botRole === 1 ? 1 : 0);
}

function hasParticipant(room, role) {
  return Boolean(room.clients[role]) || room.botRole === role;
}

function canStartCountdown(room) {
  return hasParticipant(room, 0) && hasParticipant(room, 1);
}

function resetRoom(room, status = null) {
  const names = room.players.map((p) => p.name);
  room.players = [createPlayer(0, names[0] || 'Player 1', room.rules), createPlayer(1, names[1] || 'Player 2', room.rules)];
  room.status = status || (canStartCountdown(room) ? 'countdown' : 'waiting');
  if (room.status === 'countdown' && !canStartCountdown(room)) room.status = 'waiting';
  room.winner = -1;
  room.countdownRemaining = room.status === 'countdown' ? ROOM_COUNTDOWN_SECONDS : 0;
  room.time = 0;
  room.balls = [createBall(room.rules)];
  room.bricks = createBricks(room.rules);
  room.projectiles = [];
  room.powerups = [];
  room.events = [];
  if (room.status === 'countdown') addEvent(room, `Debut dans ${Math.ceil(room.countdownRemaining)}s`);
  if (room.status === 'playing') addEvent(room, 'Début de manche');
}

function startCountdown(room) {
  if (!canStartCountdown(room)) {
    room.status = 'waiting';
    room.countdownRemaining = 0;
    return;
  }
  resetRoom(room, 'countdown');
}

function startPlaying(room) {
  room.status = 'playing';
  room.winner = -1;
  room.countdownRemaining = 0;
  room.time = 0;
  addEvent(room, 'DÃ©but de manche');
}

function findRoomForClient() {
  for (const room of rooms.values()) {
    if (room.public && room.status === 'waiting' && ((!room.clients[0] && room.clients[1]) || (room.clients[0] && !room.clients[1]))) {
      return room;
    }
  }
  return createRoom({ public: true });
}

function addEvent(room, message) {
  room.events.push(message);
  while (room.events.length > 8) room.events.shift();
  for (const ws of room.clients) safeSend(ws, { type: 'event', message });
}

function roomInfoPayload(room, role) {
  return {
    type: 'roomInfo',
    roomId: room.id,
    roomCode: room.code,
    role,
    host: room.hostRole === role,
    public: room.public,
    invitePath: invitePathFor(room),
    rules: room.rules
  };
}

function sendRoomInfo(room) {
  for (let role = 0; role < 2; role++) {
    safeSend(room.clients[role], roomInfoPayload(room, role));
  }
}

function firstOpenRole(room, preferredRole = -1) {
  if ((preferredRole === 0 || preferredRole === 1) && !hasParticipant(room, preferredRole)) return preferredRole;
  if (!hasParticipant(room, 0)) return 0;
  if (!hasParticipant(room, 1)) return 1;
  return -1;
}

function addClientToRoom(ws, room, name, preferredRole = -1) {
  if (!room) {
    safeSend(ws, { type: 'error', message: 'Room introuvable' });
    return false;
  }
  if (ws._brickDuelRoom) {
    safeSend(ws, { type: 'error', message: 'Deja dans une room' });
    return false;
  }
  const role = firstOpenRole(room, preferredRole);
  if (role < 0) {
    safeSend(ws, { type: 'error', message: 'Room pleine' });
    return false;
  }
  room.clients[role] = ws;
  room.players[role].name = String(name || `Player ${role + 1}`).slice(0, 20);
  if (room.hostRole === null || room.hostRole === undefined) room.hostRole = role;
  ws._brickDuelRoom = room;
  ws._brickDuelRole = role;
  safeSend(ws, { ...roomInfoPayload(room, role), type: 'welcome' });
  addEvent(room, `${room.players[role].name} rejoint la salle`);
  if (canStartCountdown(room)) startCountdown(room);
  sendRoomInfo(room);
  return true;
}

function addBotToRoom(room, role = 1) {
  if (!room || hasParticipant(room, role)) return false;
  room.botRole = role;
  room.players[role].name = 'Bot';
  addEvent(room, 'Bot rejoint la salle');
  if (canStartCountdown(room)) startCountdown(room);
  sendRoomInfo(room);
  return true;
}

function createBotRoom(ws, name) {
  const room = createRoom({ public: false });
  if (!addClientToRoom(ws, room, name, 0)) return false;
  return addBotToRoom(room, 1);
}

function addClient(ws, name) {
  return addClientToRoom(ws, findRoomForClient(), name);
}

function roomByCode(code) {
  const normalized = normalizeRoomCode(code);
  const id = roomCodes.get(normalized);
  return id ? rooms.get(id) : null;
}

function removeClient(ws) {
  const room = ws._brickDuelRoom;
  const role = ws._brickDuelRole;
  if (!room || role === undefined) return;
  if (room.clients[role] === ws) room.clients[role] = null;
  const other = role === 0 ? 1 : 0;
  if (room.clients[other]) {
    room.status = 'waiting';
    room.winner = other;
    room.countdownRemaining = 0;
    if (room.hostRole === role) room.hostRole = other;
    sendRoomInfo(room);
    addEvent(room, 'Adversaire déconnecté');
  }
  if (!room.clients[0] && !room.clients[1]) {
    rooms.delete(room.id);
    roomCodes.delete(room.code);
  }
  ws._brickDuelRoom = null;
  ws._brickDuelRole = undefined;
}

function handleMessage(ws, raw) {
  let data;
  try {
    data = JSON.parse(raw.toString());
  } catch (_) {
    safeSend(ws, { type: 'error', message: 'Message JSON invalide' });
    return;
  }
  if (!data || typeof data !== 'object') return;

  if (data.type === 'ping') {
    safeSend(ws, { type: 'pong', seq: data.seq || 0 });
    return;
  }

  if (data.type === 'createRoom') {
    if (!ws._brickDuelRoom) {
      const room = createRoom({ public: false });
      addClientToRoom(ws, room, data.name || 'Player', 0);
    }
    return;
  }

  if (data.type === 'botRoom') {
    if (!ws._brickDuelRoom) createBotRoom(ws, data.name || 'Player');
    return;
  }

  if (data.type === 'joinRoom') {
    if (!ws._brickDuelRoom) {
      const room = roomByCode(data.roomCode || data.code || data.room || '');
      addClientToRoom(ws, room, data.name || 'Player');
    }
    return;
  }

  if (data.type === 'join') {
    if (!ws._brickDuelRoom) addClient(ws, data.name || 'Player');
    return;
  }

  const room = ws._brickDuelRoom;
  const role = ws._brickDuelRole;
  if (!room || role === undefined) return;

  if (data.type === 'start') {
    if (room.hostRole === role) startCountdown(room);
    return;
  }

  const player = room.players[role];

  if (data.type === 'input') {
    player.move = clamp(Number(data.move || 0), -1, 1);
    const tx = data.targetX;
    player.targetX = typeof tx === 'number' && Number.isFinite(tx) ? clamp(tx, 45, W - 45) : null;
    const fireDown = Boolean(data.fire);
    player.firePressed = player.firePressed || (fireDown && !player.fireDown);
    if (fireDown && !player.fireDown) player.holdRepeatAt = room.time + HOLD_FIRE_INTERVAL;
    player.fireDown = fireDown;
    player.fire = fireDown;
    if (typeof data.switch === 'string' && roomWeapon(room, data.switch)) {
      player.queuedSwitch = data.switch;
    }
    if (typeof data.action === 'string' && room.status === 'playing') {
      activateAction(room, player, data.action);
    }
  } else if (data.type === 'restart') {
    startCountdown(room);
  }
}

function switchWeapon(player, weapon, room) {
  const weaponRules = roomWeapon(room, weapon);
  if (!weaponRules) return false;
  const changed = weapon !== player.active;
  player.active = weapon;
  player.ammo = player.ammoReserve[weapon] || 0;
  player.nextShotAt = Math.min(player.nextShotAt, room.time);
  if (changed) addEvent(room, `${player.name}: ${weaponRules.label}`);
  return changed;
}

function cooldownFor(player, room) {
  const weapon = roomWeapon(room, player.active);
  if (!weapon) return 0;
  const boost = player.rapidUntil > room.time ? room.rules.powerups.rapidCooldownMultiplier : 1.0;
  return weapon.cooldown * boost;
}

function beginAmmoReload(player, weaponName, room) {
  const weapon = roomWeapon(room, weaponName);
  if (!weapon) return;
  if ((player.ammoReserve[weaponName] || 0) < weapon.ammo) {
    player.ammoReloadAt[weaponName] = room.time + reloadTimeFor(player, weaponName, room);
  } else {
    player.ammoReloadAt[weaponName] = 0;
  }
}

function reloadTimeFor(player, weaponName, room) {
  const weapon = roomWeapon(room, weaponName);
  if (!weapon) return 0;
  const rapid = player.rapidUntil > room.time ? 0.5 : 1.0;
  return weapon.reload * rapid;
}

function spawnProjectile(room, player) {
  const weapon = roomWeapon(room, player.active);
  if (!weapon) return;
  const direction = player.role === 0 ? -1 : 1;
  const angles = player.splitUntil > room.time ? [-0.24, -0.08, 0.08, 0.24] : [0];
  for (const angle of angles) {
    room.projectiles.push({
      id: nextObjectId++,
      owner: player.role,
      kind: angle === 0 ? player.active : `${player.active}_split`,
      x: player.x,
      y: player.y + direction * 46,
      vx: Math.sin(angle) * weapon.speed,
      vy: direction * Math.cos(angle) * weapon.speed,
      r: weapon.radius,
      impact: weapon.impact,
      ttl: 1.55
    });
  }
}

function fireActive(room, player) {
  if (room.time < player.nextShotAt) return;
  if (player.ammo <= 0) return;
  const weapon = roomWeapon(room, player.active);
  if (!weapon) return;
  spawnProjectile(room, player);
  player.ammo -= 1;
  player.ammoReserve[player.active] = player.ammo;
  beginAmmoReload(player, player.active, room);
  player.nextShotAt = room.time + cooldownFor(player, room);
}

function activateAction(room, player, action) {
  if (!ACTION_KINDS.includes(action)) return false;
  if ((player.actionStacks[action] || 0) <= 0) return false;
  if (action === 'rapid' && player.rapidUntil > room.time) return false;
  if (action === 'shield' && player.protectedUntil > room.time) return false;
  if (action === 'split' && player.splitUntil > room.time) return false;
  player.actionStacks[action] -= 1;
  if (action === 'rapid') {
    player.rapidUntil = Math.max(player.rapidUntil, room.time + room.rules.powerups.rapidDuration);
    if ((player.ammoReloadAt.sniper || 0) > room.time) {
      player.ammoReloadAt.sniper = room.time + Math.min(player.ammoReloadAt.sniper - room.time, reloadTimeFor(player, 'sniper', room));
    }
    addEvent(room, `${player.name}: rapid active`);
  } else if (action === 'shield') {
    player.protectedUntil = Math.max(player.protectedUntil, room.time + room.rules.powerups.shieldDuration);
    addEvent(room, `${player.name}: shield actif`);
  } else if (action === 'split') {
    player.splitUntil = Math.max(player.splitUntil, room.time + room.rules.powerups.splitDuration);
    addEvent(room, `${player.name}: split actif`);
  }
  return true;
}

function updateAmmoReloads(room) {
  for (const player of room.players) {
    for (const weaponName of WEAPON_ORDER) {
      const weapon = roomWeapon(room, weaponName);
      if (player.ammoReserve[weaponName] >= weapon.ammo) {
        player.ammoReloadAt[weaponName] = 0;
        continue;
      }
      if ((player.ammoReloadAt[weaponName] || 0) <= 0) {
        player.ammoReloadAt[weaponName] = room.time + reloadTimeFor(player, weaponName, room);
      } else if (player.ammoReloadAt[weaponName] <= room.time) {
        if (weaponName === 'sniper') {
          player.ammoReserve[weaponName] = Math.min(weapon.ammo, (player.ammoReserve[weaponName] || 0) + 1);
          player.ammoReloadAt[weaponName] = player.ammoReserve[weaponName] < weapon.ammo ? room.time + reloadTimeFor(player, weaponName, room) : 0;
        } else {
          player.ammoReserve[weaponName] = weapon.ammo;
          player.ammoReloadAt[weaponName] = 0;
        }
      }
    }
    player.ammo = player.ammoReserve[player.active] || 0;
  }
}

function updateBotInput(room, dt) {
  if (room.botRole !== 0 && room.botRole !== 1) return;
  const player = room.players[room.botRole];
  if (!player) return;
  player.targetX = null;

  if (room.status !== 'playing') {
    player.move = 0;
    player.fire = false;
    player.fireDown = false;
    return;
  }

  let targetBall = room.balls[0] || null;
  for (const ball of room.balls) {
    if (!targetBall || Math.abs(ball.y - player.y) < Math.abs(targetBall.y - player.y)) targetBall = ball;
  }
  if (!targetBall) return;

  const lead = clamp(targetBall.vx * 0.22, -150, 150);
  const wobble = Math.sin(room.time * 1.7 + player.role * 2.1) * 24;
  const targetX = clamp(targetBall.x + lead + wobble, 58, W - 58);
  player.move = clamp((targetX - player.x) / 120, -1, 1);

  if (room.time >= player.aiDecisionAt) {
    const closeToBall = Math.abs(targetBall.y - player.y) < H * 0.42;
    const desiredWeapon = 'sniper';
    if (player.active !== desiredWeapon && (player.ammoReserve[desiredWeapon] || 0) > 0) player.queuedSwitch = desiredWeapon;
    player.aiDecisionAt = room.time + rand(0.45, 0.9);
  }

  const aligned = Math.abs(targetBall.x - player.x) < 110;
  const ballInLane = player.role === 1 ? targetBall.y < H * 0.72 : targetBall.y > H * 0.28;
  if (aligned && ballInLane && room.time >= player.aiNextFireAt) {
    player.fire = true;
    player.fireDown = true;
    player.firePressed = true;
    player.aiNextFireAt = room.time + rand(0.38, 0.78);
  } else {
    player.fire = false;
    player.fireDown = false;
  }
}

function updatePlayers(room, dt) {
  updateBotInput(room, dt);
  for (const player of room.players) {
    if (player.queuedSwitch) {
      const requestedWeapon = player.queuedSwitch;
      const changedWeapon = switchWeapon(player, requestedWeapon, room);
      if (player.fireDown && changedWeapon) {
        player.firePressed = true;
      }
      player.queuedSwitch = '';
    }

    if (player.targetX !== null) {
      player.x = player.targetX;
    } else if (player.move !== 0) {
      player.x += player.move * room.rules.player.speed * dt;
    }
    player.x = clamp(player.x, 58, W - 58);
    player.y = PLAYER_Y[player.role];
    if (player.firePressed) {
      fireActive(room, player);
      player.holdRepeatAt = room.time + HOLD_FIRE_INTERVAL;
    } else if (player.fireDown && room.time >= player.holdRepeatAt) {
      fireActive(room, player);
      player.holdRepeatAt = room.time + HOLD_FIRE_INTERVAL;
    }
    player.firePressed = false;
  }
}

function brickProtected(room, owner) {
  const player = room.players[owner];
  return player && player.protectedUntil > room.time;
}

function destroyBrick(room, brick) {
  if (!brick.alive) return;
  brick.alive = false;
  const owner = brick.owner;
  if (brick.powerupKind) {
    room.powerups.push({
      id: nextObjectId++,
      owner,
      kind: brick.powerupKind,
      x: brick.x + brick.w / 2,
      y: brick.y + brick.h / 2,
      r: 24,
      ttl: 6.5
    });
  }
}

function bounceBallOffRect(ball, rect) {
  const fromTop = ball.y < rect.y;
  const fromBottom = ball.y > rect.y + rect.h;
  if (fromTop) {
    ball.y = rect.y - ball.r - 1;
    ball.vy = -Math.abs(ball.vy);
  } else if (fromBottom) {
    ball.y = rect.y + rect.h + ball.r + 1;
    ball.vy = Math.abs(ball.vy);
  } else if (ball.x < rect.x + rect.w * 0.5) {
    ball.x = rect.x - ball.r - 1;
    ball.vx = -Math.abs(ball.vx);
  } else {
    ball.x = rect.x + rect.w + ball.r + 1;
    ball.vx = Math.abs(ball.vx);
  }
}

function bounceBallOffPlayer(room, ball, player, rect, prevX, prevY) {
  bounceBallOffRect(ball, rect);
  ball.lastPlayerBounceRole = player.role;
  ball.lastPlayerBounceAt = room.time;
  normalizeBall(ball, room);
}

function updateBall(room, ball, dt) {
  const prevX = ball.x;
  const prevY = ball.y;
  ball.x += ball.vx * dt;
  ball.y += ball.vy * dt;

  if (ball.x - ball.r < 16) {
    ball.x = 16 + ball.r;
    ball.vx = Math.abs(ball.vx);
  } else if (ball.x + ball.r > W - 16) {
    ball.x = W - 16 - ball.r;
    ball.vx = -Math.abs(ball.vx);
  }

  if (ball.y - ball.r < 16) {
    ball.y = 16 + ball.r;
    ball.vy = Math.abs(ball.vy);
  } else if (ball.y + ball.r > H - 16) {
    ball.y = H - 16 - ball.r;
    ball.vy = -Math.abs(ball.vy);
  }

  for (const player of room.players) {
    const rect = { x: player.x - PLAYER_W / 2, y: player.y - PLAYER_H / 2, w: PLAYER_W, h: PLAYER_H };
    if (circleRectCollides(ball.x, ball.y, ball.r, rect)) {
      bounceBallOffPlayer(room, ball, player, rect, prevX, prevY);
      break;
    }
  }

  for (const brick of room.bricks) {
    if (!brick.alive) continue;
    if (!circleRectCollides(ball.x, ball.y, ball.r, brick)) continue;
    if (!brickProtected(room, brick.owner)) destroyBrick(room, brick);
    bounceBallOffRect(ball, brick);
    ball.vx += rand(-18, 18);
    ball.vy *= 1.012;
    normalizeBall(ball, room);
    break;
  }
}

function clampBallToArena(ball) {
  ball.x = clamp(ball.x, 16 + ball.r, W - 16 - ball.r);
  ball.y = clamp(ball.y, 16 + ball.r, H - 16 - ball.r);
}

function resolveBallCollision(room, a, b) {
  let dx = a.x - b.x;
  let dy = a.y - b.y;
  let dist = Math.hypot(dx, dy);
  const minDist = a.r + b.r;
  if (dist >= minDist) return;

  if (dist < 0.001) {
    dx = rand(-1, 1) || 1;
    dy = rand(-1, 1);
    dist = Math.hypot(dx, dy);
  }

  const nx = dx / dist;
  const ny = dy / dist;
  const overlap = minDist - dist;
  a.x += nx * overlap * 0.5;
  a.y += ny * overlap * 0.5;
  b.x -= nx * overlap * 0.5;
  b.y -= ny * overlap * 0.5;
  clampBallToArena(a);
  clampBallToArena(b);

  const relVel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
  if (relVel >= 0) return;
  a.vx -= relVel * nx;
  a.vy -= relVel * ny;
  b.vx += relVel * nx;
  b.vy += relVel * ny;
  normalizeBall(a, room);
  normalizeBall(b, room);
}

function updateBalls(room, dt) {
  for (const ball of room.balls) updateBall(room, ball, dt);
  for (let i = 0; i < room.balls.length; i++) {
    for (let j = i + 1; j < room.balls.length; j++) {
      resolveBallCollision(room, room.balls[i], room.balls[j]);
    }
  }
}

function updateProjectiles(room, dt) {
  const survivors = [];
  for (const projectile of room.projectiles) {
    const prevX = projectile.x;
    const prevY = projectile.y;
    projectile.x += projectile.vx * dt;
    projectile.y += projectile.vy * dt;
    projectile.ttl -= dt;
    let alive = projectile.ttl > 0 && projectile.x > -40 && projectile.x < W + 40 && projectile.y > -60 && projectile.y < H + 60;

    if (alive) {
      for (const ball of room.balls) {
        const hit = segmentCircleCollision(prevX, prevY, projectile.x, projectile.y, ball.x, ball.y, projectile.r + ball.r);
        if (!hit) continue;
        projectile.x = hit.x;
        projectile.y = hit.y;
        applyProjectileBallImpact(room, projectile, ball);
        normalizeBall(ball, room);
        alive = false;
        break;
      }
    }

    if (alive) survivors.push(projectile);
  }
  room.projectiles = survivors;
}

function applyProjectileBallImpact(room, projectile, ball) {
  const dx = ball.x - projectile.x;
  const dy = ball.y - projectile.y;
  const distance = Math.hypot(dx, dy) || 1;
  const nx = dx / distance;
  const projectileSpeed = Math.hypot(projectile.vx, projectile.vy) || room.rules.ball.minSpeed;
  const baseImpulse = projectileSpeed * projectile.impact;
  const sideHit = clamp(Math.abs(nx), 0, 1);
  const sideImpulse = nx * baseImpulse * (0.12 + sideHit * 0.38);

  ball.vx += projectile.vx * projectile.impact * 0.28 + sideImpulse + rand(-4, 4);
  ball.vy += projectile.vy * projectile.impact * (1.0 - sideHit * 0.18);
}

function applyPowerup(room, player, powerup) {
  if (!ACTION_KINDS.includes(powerup.kind)) return;
  player.actionStacks[powerup.kind] = (player.actionStacks[powerup.kind] || 0) + 1;
  if (powerup.kind === 'shield') {
    addEvent(room, `${player.name}: +1 shield`);
  } else if (powerup.kind === 'rapid') {
    addEvent(room, `${player.name}: +1 rapid`);
  } else if (powerup.kind === 'split') {
    addEvent(room, `${player.name}: +1 split`);
  }
}

function updatePowerups(room, dt) {
  const survivors = [];
  for (const powerup of room.powerups) {
    powerup.ttl -= dt;
    const owner = room.players[powerup.owner];
    const direction = powerup.owner === 0 ? 1 : -1;
    powerup.y += direction * room.rules.powerups.speed * dt;
    let collected = false;
    if (owner) {
      const rect = { x: owner.x - PLAYER_W / 2 - 10, y: owner.y - PLAYER_H / 2 - 10, w: PLAYER_W + 20, h: PLAYER_H + 20 };
      collected = circleRectCollides(powerup.x, powerup.y, powerup.r, rect);
      if (collected) applyPowerup(room, owner, powerup);
    }
    const missed = (powerup.owner === 0 && powerup.y > H + powerup.r) || (powerup.owner === 1 && powerup.y < -powerup.r);
    if (!collected && !missed && powerup.ttl > 0) survivors.push(powerup);
  }
  room.powerups = survivors;
}

function checkVictory(room) {
  for (const role of [0, 1]) {
    const alive = room.bricks.some((brick) => brick.owner === role && brick.alive);
    if (!alive) {
      room.status = 'ended';
      room.winner = role === 0 ? 1 : 0;
      addEvent(room, `${room.players[room.winner].name} gagne la manche`);
      return;
    }
  }
}

function tickRoom(room, dt) {
  if (room.status === 'countdown') {
    if (connectedCount(room) < 2) {
      room.status = 'waiting';
      room.countdownRemaining = 0;
      return;
    }
    room.countdownRemaining = Math.max(0, room.countdownRemaining - dt);
    if (room.countdownRemaining <= 0) startPlaying(room);
    return;
  }
  if (room.status !== 'playing') return;
  room.time += dt;
  updateAmmoReloads(room);
  updatePlayers(room, dt);
  updateProjectiles(room, dt);
  updateBalls(room, dt);
  updatePowerups(room, dt);
  checkVictory(room);
}

function ballSnapshot(ball) {
  return {
    id: ball.id,
    x: Math.round(ball.x * 10) / 10,
    y: Math.round(ball.y * 10) / 10,
    vx: Math.round(ball.vx * 10) / 10,
    vy: Math.round(ball.vy * 10) / 10,
    r: ball.r
  };
}

function ammoReloadSnapshot(room, player) {
  const reloads = {};
  for (const weapon of WEAPON_ORDER) {
    reloads[weapon] = Math.max(0, Math.round(((player.ammoReloadAt[weapon] || 0) - room.time) * 10) / 10);
  }
  return reloads;
}

function playerSnapshot(room, player) {
  const shieldRemaining = Math.max(0, player.protectedUntil - room.time);
  const rapidRemaining = Math.max(0, player.rapidUntil - room.time);
  const splitRemaining = Math.max(0, player.splitUntil - room.time);
  return {
    role: player.role,
    name: player.name,
    x: Math.round(player.x * 10) / 10,
    y: player.y,
    active: player.active,
    ammo: player.ammo,
    ammoReserve: { ...player.ammoReserve },
    ammoReload: ammoReloadSnapshot(room, player),
    actionStacks: { ...player.actionStacks },
    cooldown: Math.max(0, Math.round((player.nextShotAt - room.time) * 10) / 10),
    cooldownMax: Math.round(cooldownFor(player, room) * 100) / 100,
    protected: shieldRemaining > 0,
    shield: Math.round(shieldRemaining * 10) / 10,
    shieldMax: room.rules.powerups.shieldDuration,
    rapid: Math.round(rapidRemaining * 10) / 10,
    rapidMax: room.rules.powerups.rapidDuration,
    split: Math.round(splitRemaining * 10) / 10,
    splitMax: room.rules.powerups.splitDuration
  };
}

function snapshot(room, role) {
  const balls = room.balls.map((ball) => ballSnapshot(ball));
  return {
    type: 'state',
    roomId: room.id,
    roomCode: room.code,
    invitePath: invitePathFor(room),
    public: room.public,
    host: room.hostRole === role,
    rules: room.rules,
    you: role,
    status: room.status,
    winner: room.winner,
    playerCount: connectedCount(room),
    capacity: 2,
    countdown: Math.max(0, Math.round((room.countdownRemaining || 0) * 10) / 10),
    message: room.status === 'waiting' ? 'En attente d\'un adversaire...' : (room.status === 'countdown' ? `Debut dans ${Math.ceil(room.countdownRemaining || 0)}s` : ''),
    t: Math.round(room.time * 1000) / 1000,
    w: W,
    h: H,
    players: room.players.map((p) => playerSnapshot(room, p)),
    ball: balls[0] || {},
    balls,
    bricks: room.bricks.map((b) => ({
      id: b.id,
      owner: b.owner,
      x: b.x,
      y: b.y,
      w: b.w,
      h: b.h,
      alive: b.alive,
      protected: b.alive && brickProtected(room, b.owner)
    })),
    projectiles: room.projectiles.map((p) => ({
      id: p.id,
      owner: p.owner,
      kind: p.kind,
      x: Math.round(p.x * 10) / 10,
      y: Math.round(p.y * 10) / 10,
      vx: Math.round(p.vx * 10) / 10,
      vy: Math.round(p.vy * 10) / 10
    })),
    powerups: room.powerups.map((p) => ({
      id: p.id,
      owner: p.owner,
      kind: p.kind,
      x: Math.round(p.x * 10) / 10,
      y: Math.round(p.y * 10) / 10
    }))
  };
}

function broadcastSnapshots() {
  for (const room of rooms.values()) {
    for (let role = 0; role < 2; role++) {
      safeSend(room.clients[role], snapshot(room, role));
    }
  }
}

function contentType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.html') return 'text/html; charset=utf-8';
  if (ext === '.js') return 'application/javascript; charset=utf-8';
  if (ext === '.wasm') return 'application/wasm';
  if (ext === '.pck') return 'application/octet-stream';
  if (ext === '.png') return 'image/png';
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.css') return 'text/css; charset=utf-8';
  return 'application/octet-stream';
}

function staticHeaders(filePath) {
  const headers = {
    'Content-Type': contentType(filePath),
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin'
  };
  if (['.html', '.js', '.wasm', '.pck'].includes(path.extname(filePath).toLowerCase())) headers['Cache-Control'] = 'no-store';
  return headers;
}

function serveStatic(req, res) {
  let pathname = decodeURIComponent(new URL(req.url, `${HTTPS_ENABLED ? 'https' : 'http'}://${req.headers.host}`).pathname);
  if (pathname === '/') pathname = '/index.html';
  const filePath = path.normalize(path.join(STATIC_ROOT, pathname));
  if (!filePath.startsWith(path.normalize(STATIC_ROOT))) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      if (pathname === '/index.html') {
        res.writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cross-Origin-Opener-Policy': 'same-origin',
          'Cross-Origin-Embedder-Policy': 'require-corp',
          'Cross-Origin-Resource-Policy': 'same-origin'
        });
        res.end(`<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Breakshot Server</title>
<style>body{font-family:system-ui;background:#0f172a;color:#e5e7eb;padding:32px;line-height:1.5}code{background:#111827;padding:2px 6px;border-radius:6px}</style></head>
<body><h1>Breakshot Server actif</h1><p>WebSocket prêt sur <code>ws://localhost:${PORT}</code>.</p><p>Exportez le projet Godot Web vers <code>web_export/index.html</code>, puis rechargez cette page.</p></body></html>`);
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Not found');
      }
      return;
    }
    res.writeHead(200, staticHeaders(filePath));
    res.end(data);
  });
}

function tlsOptions() {
  const options = {
    key: fs.readFileSync(HTTPS_KEY),
    cert: fs.readFileSync(HTTPS_CERT)
  };
  if (HTTPS_CA !== '') options.ca = fs.readFileSync(HTTPS_CA);
  return options;
}

function createAppServer() {
  if (HTTPS_ENABLED) return https.createServer(tlsOptions(), serveStatic);
  return http.createServer(serveStatic);
}

const appServer = createAppServer();
const wss = new WebSocket.Server({ server: appServer });

wss.on('connection', (ws) => {
  ws.on('message', (raw) => handleMessage(ws, raw));
  ws.on('close', () => removeClient(ws));
  ws.on('error', () => removeClient(ws));
  safeSend(ws, { type: 'event', message: 'Connecté au serveur Breakshot' });
});

setInterval(() => {
  for (const room of rooms.values()) tickRoom(room, DT);
}, 1000 / TICK_RATE);

setInterval(broadcastSnapshots, 1000 / SNAPSHOT_RATE);

if (HTTPS_ENABLED && REDIRECT_HTTP_PORT > 0) {
  http.createServer((req, res) => {
    const host = String(req.headers.host || `localhost:${REDIRECT_HTTP_PORT}`).replace(/:\d+$/, `:${PORT}`);
    res.writeHead(308, { Location: `https://${host}${req.url}` });
    res.end();
  }).listen(REDIRECT_HTTP_PORT, () => {
    console.log(`HTTP redirect listening on http://localhost:${REDIRECT_HTTP_PORT}`);
  });
}

appServer.listen(PORT, () => {
  const protocol = HTTPS_ENABLED ? 'https' : 'http';
  const wsProtocol = HTTPS_ENABLED ? 'wss' : 'ws';
  console.log(`Breakshot server listening on ${protocol}://localhost:${PORT}`);
  console.log(`WebSocket endpoint: ${wsProtocol}://localhost:${PORT}`);
  console.log(`Static web export root: ${STATIC_ROOT}`);
});
