'use strict';

const W = 720;
const H = 1280;
const TICK_RATE = 60;
const SNAPSHOT_RATE = 60;
const DT = 1 / TICK_RATE;
const ROOM_COUNTDOWN_SECONDS = 4.0;

const PLAYER_SPEED = 760;
const PLAYER_W = 118;
const PLAYER_H = 34;
const PLAYER_Y = [1164, 139];
const BALL_R = 17;
const BALL_MIN_SPEED = 0;
const BALL_MAX_SPEED = 920;
const POWERUP_CHANCE = 0.36;
const POWERUP_SPEED = 165;
const HOLD_FIRE_INTERVAL = 0.22;

const BRICK_COLS = 7;
const BRICK_ROWS = 4;
const BRICK_W = 80;
const BRICK_H = 31;
const BRICK_GAP = 7;
const BRICK_X0 = (W - (BRICK_COLS * BRICK_W + (BRICK_COLS - 1) * BRICK_GAP)) / 2;
const WALL_Y = {
  1: 228,
  0: 930
};

const WEAPONS = {
  sniper: { label: 'Sniper', ammo: 5, cooldown: 0, reload: 0.8, speed: 2240, radius: 9, impact: 0.575, semi: false }
};
const WEAPON_ORDER = Object.keys(WEAPONS);
const POWER_KINDS = ['shield', 'rapid', 'split'];
const ACTION_KINDS = ['rapid', 'shield', 'split'];
const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const ROOM_CODE_LENGTH = 5;

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function cleanNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return clamp(number, min, max);
}

function cleanInt(value, fallback, min, max) {
  return Math.round(cleanNumber(value, fallback, min, max));
}

function cleanBool(value, fallback) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
    if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  }
  return fallback;
}

function objectOrEmpty(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function cloneDefaultRules() {
  return {
    version: 1,
    player: {
      speed: PLAYER_SPEED
    },
    ball: {
      radius: BALL_R,
      minSpeed: BALL_MIN_SPEED,
      maxSpeed: BALL_MAX_SPEED,
      serveSpeedMin: 440,
      serveSpeedMax: 540
    },
    powerups: {
      chance: POWERUP_CHANCE,
      speed: POWERUP_SPEED,
      shieldDuration: 1.0,
      rapidDuration: 5.0,
      splitDuration: 3.0,
      rapidCooldownMultiplier: 0.65
    },
    weapons: Object.fromEntries(WEAPON_ORDER.map((name) => [name, { ...WEAPONS[name] }]))
  };
}

function sanitizeRules(input = {}) {
  const decodedInput = objectOrEmpty(input);
  const defaults = cloneDefaultRules();
  const rules = cloneDefaultRules();
  const player = objectOrEmpty(decodedInput.player);
  const ball = objectOrEmpty(decodedInput.ball);
  const powerups = objectOrEmpty(decodedInput.powerups);
  const weapons = objectOrEmpty(decodedInput.weapons);

  rules.player.speed = cleanNumber(player.speed, defaults.player.speed, 180, 1800);

  rules.ball.radius = cleanNumber(ball.radius, defaults.ball.radius, 5, 56);
  rules.ball.minSpeed = cleanNumber(ball.minSpeed, defaults.ball.minSpeed, 0, 1600);
  rules.ball.maxSpeed = cleanNumber(ball.maxSpeed, defaults.ball.maxSpeed, rules.ball.minSpeed, 2400);
  rules.ball.serveSpeedMin = cleanNumber(ball.serveSpeedMin, defaults.ball.serveSpeedMin, rules.ball.minSpeed, rules.ball.maxSpeed);
  rules.ball.serveSpeedMax = cleanNumber(ball.serveSpeedMax, defaults.ball.serveSpeedMax, rules.ball.serveSpeedMin, rules.ball.maxSpeed);

  rules.powerups.chance = cleanNumber(powerups.chance, defaults.powerups.chance, 0, 1);
  rules.powerups.speed = cleanNumber(powerups.speed, defaults.powerups.speed, 0, 520);
  rules.powerups.shieldDuration = cleanNumber(powerups.shieldDuration, defaults.powerups.shieldDuration, 0.1, 12);
  rules.powerups.rapidDuration = cleanNumber(powerups.rapidDuration, defaults.powerups.rapidDuration, 0.1, 18);
  rules.powerups.splitDuration = cleanNumber(powerups.splitDuration, defaults.powerups.splitDuration, 0.1, 12);
  rules.powerups.rapidCooldownMultiplier = cleanNumber(powerups.rapidCooldownMultiplier, defaults.powerups.rapidCooldownMultiplier, 0.05, 1.5);

  for (const weaponName of WEAPON_ORDER) {
    const fallback = defaults.weapons[weaponName];
    const source = objectOrEmpty(weapons[weaponName]);
    const target = rules.weapons[weaponName];
    if (typeof source.label === 'string' && source.label.trim() !== '') target.label = source.label.slice(0, 24);
    target.ammo = cleanInt(source.ammo, fallback.ammo, 0, 99);
    target.cooldown = cleanNumber(source.cooldown, fallback.cooldown, 0, 12);
    target.reload = cleanNumber(source.reload, fallback.reload, 0.05, 30);
    if (fallback.speed !== undefined) target.speed = cleanNumber(source.speed, fallback.speed, 80, 2500);
    if (fallback.radius !== undefined) target.radius = cleanNumber(source.radius, fallback.radius, 2, 32);
    if (fallback.impact !== undefined) target.impact = cleanNumber(source.impact, fallback.impact, 0, 3);
    if (fallback.pellets !== undefined) target.pellets = cleanInt(source.pellets, fallback.pellets, 1, 16);
    if (fallback.spread !== undefined) target.spread = cleanNumber(source.spread, fallback.spread, 0, 1.2);
    if (fallback.duration !== undefined) target.duration = cleanNumber(source.duration, fallback.duration, 0.1, 12);
    if (fallback.semi !== undefined) target.semi = cleanBool(source.semi, fallback.semi);
  }

  return rules;
}

function roomWeapon(room, weaponName) {
  return room && room.rules && room.rules.weapons ? room.rules.weapons[weaponName] : WEAPONS[weaponName];
}

module.exports = {
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
};
