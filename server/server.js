'use strict';

const http          = require('http');
const { Server }    = require('socket.io');
const Database      = require('better-sqlite3');
const path          = require('path');
const { URL }       = require('url');

// ── Database setup ─────────────────────────────────────────────────────────────
const DB_PATH = path.join(__dirname, 'resistance.db');
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.exec(`
  CREATE TABLE IF NOT EXISTS players (
    uuid        TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    xp          INTEGER NOT NULL DEFAULT 0,
    rank        INTEGER NOT NULL DEFAULT 1,
    login_streak INTEGER NOT NULL DEFAULT 0,
    last_login  TEXT,
    total_kills INTEGER NOT NULL DEFAULT 0,
    total_games INTEGER NOT NULL DEFAULT 0,
    best_wave   INTEGER NOT NULL DEFAULT 0,
    best_coop_wave INTEGER NOT NULL DEFAULT 0,
    medals      TEXT NOT NULL DEFAULT '[]',
    title       TEXT NOT NULL DEFAULT 'Survivor',
    created_at  TEXT NOT NULL DEFAULT (date('now'))
  );
  CREATE TABLE IF NOT EXISTS sessions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid        TEXT NOT NULL,
    wave        INTEGER NOT NULL,
    kills       INTEGER NOT NULL,
    duration_s  INTEGER NOT NULL DEFAULT 0,
    is_coop     INTEGER NOT NULL DEFAULT 0,
    partner_uuid TEXT,
    op_week     TEXT,
    played_at   TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS challenges (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    from_uuid   TEXT NOT NULL,
    to_uuid     TEXT NOT NULL,
    from_name   TEXT NOT NULL,
    wave        INTEGER NOT NULL,
    kills       INTEGER NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS weekly_ops (
    week_key    TEXT PRIMARY KEY,
    modifier    TEXT NOT NULL,
    title       TEXT NOT NULL,
    description TEXT NOT NULL
  );
`);

// ── Rank thresholds (XP needed to reach rank N) ───────────────────────────────
const RANK_TITLES = [
  '', // 0 unused
  'Survivor', 'Recruit', 'Scout', 'Ranger', 'Corporal',
  'Sergeant', 'Staff Sergeant', 'Master Sergeant', 'Warrant Officer', 'Lieutenant',
  'Captain', 'Major', 'Lt. Colonel', 'Colonel', 'Brigadier',
  'General', 'Commander', 'Shadow Operative', 'Elite Shadow', 'Shadow Commander'
];
function getRankForXP(xp) {
  // Every 500 XP = 1 rank, capped at 20
  return Math.min(20, Math.max(1, Math.floor(xp / 500) + 1));
}

// ── Weekly operation schedule ─────────────────────────────────────────────────
const WEEKLY_OP_POOL = [
  { modifier: 'pistol_only',    title: 'IRON WEEK',       description: 'Pistol only. No upgrades. No excuses.' },
  { modifier: 'double_bugs',    title: 'BUG INVASION',    description: '2× bug spawn rate. Swarm conditions.' },
  { modifier: 'no_towers',      title: 'BARE HANDED',     description: 'No defense towers. Hold with what you have.' },
  { modifier: 'fast_waves',     title: 'RAPID ASSAULT',   description: 'Build phase cut to 15s. React fast.' },
  { modifier: 'elite_enemies',  title: 'ELITE FORCES',    description: 'All enemies have 50% more HP.' },
  { modifier: 'coin_frenzy',    title: 'GOLD RUSH',       description: 'Enemies drop 2× coins. Upgrade everything.' },
  { modifier: 'normal',         title: 'STANDARD OPS',    description: 'No modifiers. Prove your skill.' },
];
function getWeekKey(date) {
  const d = date || new Date();
  const jan1 = new Date(d.getFullYear(), 0, 1);
  const week = Math.ceil(((d - jan1) / 86400000 + jan1.getDay() + 1) / 7);
  return `${d.getFullYear()}-W${String(week).padStart(2, '0')}`;
}
function ensureWeeklyOp() {
  const key = getWeekKey();
  const existing = db.prepare('SELECT * FROM weekly_ops WHERE week_key = ?').get(key);
  if (existing) return existing;
  const op = WEEKLY_OP_POOL[Math.abs(parseInt(key.replace(/\D/g,''), 10)) % WEEKLY_OP_POOL.length];
  db.prepare('INSERT INTO weekly_ops (week_key, modifier, title, description) VALUES (?,?,?,?)')
    .run(key, op.modifier, op.title, op.description);
  return { week_key: key, ...op };
}

// ── Daily missions (deterministic by date seed) ───────────────────────────────
const MISSION_POOL = [
  { id: 'kill_30',    label: 'Kill 30 enemies',          type: 'kills',   target: 30,  xp: 150, coins: 25 },
  { id: 'kill_50',    label: 'Kill 50 enemies',          type: 'kills',   target: 50,  xp: 250, coins: 40 },
  { id: 'reach_5',    label: 'Reach Wave 5',             type: 'wave',    target: 5,   xp: 200, coins: 30 },
  { id: 'reach_7',    label: 'Reach Wave 7',             type: 'wave',    target: 7,   xp: 400, coins: 60 },
  { id: 'airstrike_2',label: 'Use airstrike 2 times',   type: 'airstrike',target: 2,  xp: 120, coins: 20 },
  { id: 'play_coop',  label: 'Play a co-op game',        type: 'coop',    target: 1,   xp: 200, coins: 35 },
  { id: 'build_5',    label: 'Place 5 structures',       type: 'builds',  target: 5,   xp: 100, coins: 15 },
  { id: 'survive_w3', label: 'Survive Wave 3 uninjured', type: 'wave_hp', target: 3,   xp: 300, coins: 50 },
  { id: 'kill_tank',  label: 'Defeat the Tank boss',     type: 'boss',    target: 1,   xp: 500, coins: 80 },
  { id: 'play_2',     label: 'Play 2 games today',       type: 'games',   target: 2,   xp: 150, coins: 25 },
];
function getDailyMissions(dateStr) {
  // seed by date string → always same 3 for all players on same day
  let seed = 0;
  for (let i = 0; i < dateStr.length; i++) seed = (seed * 31 + dateStr.charCodeAt(i)) >>> 0;
  const indices = [];
  let s = seed;
  while (indices.length < 3) {
    s = (s * 1664525 + 1013904223) >>> 0;
    const idx = s % MISSION_POOL.length;
    if (!indices.includes(idx)) indices.push(idx);
  }
  return indices.map(i => MISSION_POOL[i]);
}

// ── Medal definitions ──────────────────────────────────────────────────────────
const MEDAL_CHECKS = [
  { id: 'first_blood',   label: 'First Blood',      check: (p, s) => p.total_kills >= 1 },
  { id: 'wave5',         label: 'Wave 5 Survivor',  check: (p, s) => s.wave >= 5 },
  { id: 'wave7',         label: 'Iron Will',         check: (p, s) => s.wave >= 7 },
  { id: 'wave10',        label: 'Legend',            check: (p, s) => p.best_wave >= 10 },
  { id: 'wave15',        label: 'Legendary',         check: (p, s) => p.best_wave >= 15 },
  { id: 'coop_debut',    label: 'Co-op Debut',       check: (p, s) => s.is_coop === 1 },
  { id: 'veteran',       label: 'Veteran',           check: (p, s) => p.total_games >= 10 },
  { id: 'fifty_games',   label: 'The Resistance',    check: (p, s) => p.total_games >= 50 },
  { id: 'boss_slayer',   label: 'Boss Slayer',       check: (p, s) => s.wave >= 7 },
  { id: 'kill100',       label: 'Century',           check: (p, s) => p.total_kills >= 100 },
  { id: 'kill500',       label: 'Executioner',       check: (p, s) => p.total_kills >= 500 },
];

// ── Streak bonus helper ────────────────────────────────────────────────────────
function getStreakBonus(streak) {
  if (streak >= 30) return { coins: 0,  weapon: 3,   label: 'Start with Rifle + bonus XP', xp_mult: 1.5 };
  if (streak >= 14) return { coins: 0,  weapon: 2,   label: 'Start with Rifle',             xp_mult: 1.0 };
  if (streak >=  7) return { coins: 50, weapon: 0,   label: '+50 starting coins',           xp_mult: 1.0 };
  if (streak >=  3) return { coins: 30, weapon: 1,   label: 'Start with Shotgun',           xp_mult: 1.0 };
  if (streak >=  1) return { coins: 15, weapon: 0,   label: '+15 starting coins',           xp_mult: 1.0 };
  return { coins: 0, weapon: 0, label: '', xp_mult: 1.0 };
}

// ── HTTP server with REST + Socket.IO ─────────────────────────────────────────
const server = http.createServer((req, res) => {
  const base = `http://${req.headers.host}`;
  let u;
  try { u = new URL(req.url, base); } catch { res.writeHead(400); res.end(); return; }
  const method = req.method.toUpperCase();

  const json = (code, obj) => {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify(obj));
  };
  const readBody = () => new Promise((resolve, reject) => {
    let body = '';
    req.on('data', c => { body += c; if (body.length > 65536) reject(new Error('body too large')); });
    req.on('end', () => { try { resolve(JSON.parse(body || '{}')); } catch { reject(new Error('bad json')); } });
    req.on('error', reject);
  });

  // OPTIONS preflight
  if (method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' });
    res.end(); return;
  }

  // POST /player/register  { uuid, name }
  if (method === 'POST' && u.pathname === '/player/register') {
    readBody().then(body => {
      const { uuid, name } = body;
      if (!uuid || !name) { json(400, { error: 'uuid and name required' }); return; }
      const today = new Date().toISOString().slice(0, 10);
      let player = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);
      if (!player) {
        db.prepare('INSERT INTO players (uuid, name, last_login) VALUES (?,?,?)').run(uuid, name.toUpperCase().slice(0, 20), today);
        player = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);
      } else {
        db.prepare('UPDATE players SET name = ? WHERE uuid = ?').run(name.toUpperCase().slice(0, 20), uuid);
        player = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);
      }
      // Streak logic
      let streak = player.login_streak;
      const last = player.last_login;
      if (last !== today) {
        const yesterday = new Date(); yesterday.setDate(yesterday.getDate() - 1);
        const yStr = yesterday.toISOString().slice(0, 10);
        streak = (last === yStr) ? streak + 1 : 1;
        db.prepare('UPDATE players SET login_streak = ?, last_login = ? WHERE uuid = ?').run(streak, today, uuid);
        player = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);
      }
      const bonus  = getStreakBonus(streak);
      const missions = getDailyMissions(today);
      const weeklyOp = ensureWeeklyOp();
      json(200, {
        uuid: player.uuid, name: player.name, xp: player.xp, rank: player.rank,
        title: RANK_TITLES[player.rank] || 'Survivor',
        login_streak: player.login_streak, streak_bonus: bonus,
        total_kills: player.total_kills, total_games: player.total_games,
        best_wave: player.best_wave, best_coop_wave: player.best_coop_wave,
        medals: JSON.parse(player.medals || '[]'),
        daily_missions: missions, weekly_op: weeklyOp,
      });
    }).catch(e => json(400, { error: e.message }));
    return;
  }

  // POST /session  { uuid, wave, kills, duration_s, is_coop, partner_uuid, op_week }
  if (method === 'POST' && u.pathname === '/session') {
    readBody().then(body => {
      const { uuid, wave, kills, duration_s, is_coop, partner_uuid, op_week } = body;
      if (!uuid || wave == null || kills == null) { json(400, { error: 'uuid, wave, kills required' }); return; }
      const player = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);
      if (!player) { json(404, { error: 'player not found' }); return; }

      // Record session
      db.prepare('INSERT INTO sessions (uuid, wave, kills, duration_s, is_coop, partner_uuid, op_week) VALUES (?,?,?,?,?,?,?)')
        .run(uuid, wave, kills, duration_s || 0, is_coop ? 1 : 0, partner_uuid || null, op_week || null);

      // Update player stats
      const newBestWave     = Math.max(player.best_wave, wave);
      const newBestCoop     = is_coop ? Math.max(player.best_coop_wave, wave) : player.best_coop_wave;
      const xpGained        = Math.round(wave * 10 + kills * 2);
      const newXP           = player.xp + xpGained;
      const newRank         = getRankForXP(newXP);
      const rankedUp        = newRank > player.rank;

      db.prepare(`UPDATE players SET xp=?, rank=?, total_kills=total_kills+?, total_games=total_games+1,
                  best_wave=?, best_coop_wave=? WHERE uuid=?`)
        .run(newXP, newRank, kills, newBestWave, newBestCoop, uuid);

      const updated = db.prepare('SELECT * FROM players WHERE uuid = ?').get(uuid);

      // Medal checks
      const currentMedals = JSON.parse(updated.medals || '[]');
      const sessionData = { wave, kills, is_coop: is_coop ? 1 : 0 };
      const newMedals = [];
      for (const m of MEDAL_CHECKS) {
        if (!currentMedals.includes(m.id) && m.check(updated, sessionData)) {
          currentMedals.push(m.id);
          newMedals.push({ id: m.id, label: m.label });
        }
      }
      if (newMedals.length > 0) {
        db.prepare('UPDATE players SET medals = ? WHERE uuid = ?').run(JSON.stringify(currentMedals), uuid);
      }

      json(200, {
        xp_gained: xpGained, new_xp: newXP, new_rank: newRank,
        new_title: RANK_TITLES[newRank] || 'Survivor',
        ranked_up: rankedUp, new_medals: newMedals,
        total_kills: updated.total_kills, total_games: updated.total_games,
        best_wave: updated.best_wave,
      });
    }).catch(e => json(400, { error: e.message }));
    return;
  }

  // GET /leaderboard/global?limit=25
  if (method === 'GET' && u.pathname === '/leaderboard/global') {
    const limit = Math.min(50, parseInt(u.searchParams.get('limit') || '25', 10));
    const rows = db.prepare('SELECT name, best_wave, rank, title FROM players ORDER BY best_wave DESC, xp DESC LIMIT ?').all(limit);
    json(200, { leaderboard: rows });
    return;
  }

  // GET /leaderboard/friends?names=A,B,C
  if (method === 'GET' && u.pathname === '/leaderboard/friends') {
    const raw = u.searchParams.get('names') || '';
    const names = raw.split(',').map(n => n.trim().toUpperCase()).filter(Boolean);
    if (names.length === 0) { json(200, { leaderboard: [] }); return; }
    const placeholders = names.map(() => '?').join(',');
    const rows = db.prepare(`SELECT name, best_wave, rank, title FROM players WHERE name IN (${placeholders}) ORDER BY best_wave DESC`).all(...names);
    json(200, { leaderboard: rows });
    return;
  }

  // GET /leaderboard/weekly?limit=25
  if (method === 'GET' && u.pathname === '/leaderboard/weekly') {
    const limit = Math.min(50, parseInt(u.searchParams.get('limit') || '25', 10));
    const weekStart = (() => {
      const d = new Date(); const day = d.getDay();
      d.setDate(d.getDate() - ((day + 6) % 7)); // Monday
      return d.toISOString().slice(0, 10);
    })();
    const rows = db.prepare(`
      SELECT p.name, MAX(s.wave) as best_wave_this_week, p.rank, p.title
      FROM sessions s JOIN players p ON p.uuid = s.uuid
      WHERE date(s.played_at) >= ? GROUP BY s.uuid ORDER BY best_wave_this_week DESC LIMIT ?
    `).all(weekStart, limit);
    json(200, { leaderboard: rows, week_start: weekStart });
    return;
  }

  // POST /challenge  { from_uuid, to_name, from_name, wave, kills }
  if (method === 'POST' && u.pathname === '/challenge') {
    readBody().then(body => {
      const { from_uuid, to_name, from_name, wave, kills } = body;
      if (!from_uuid || !to_name || wave == null) { json(400, { error: 'missing fields' }); return; }
      const target = db.prepare('SELECT uuid FROM players WHERE name = ?').get((to_name || '').toUpperCase());
      if (!target) { json(404, { error: 'friend not found' }); return; }
      db.prepare('INSERT INTO challenges (from_uuid, to_uuid, from_name, wave, kills) VALUES (?,?,?,?,?)')
        .run(from_uuid, target.uuid, from_name, wave, kills);
      // Notify via socket if target is online
      const targetSocketId = onlinePlayers.get(to_name.toUpperCase());
      if (targetSocketId) {
        io.to(targetSocketId).emit('challenge_received', { from_name, wave, kills });
      }
      json(200, { sent: true });
    }).catch(e => json(400, { error: e.message }));
    return;
  }

  // GET /challenges?uuid=...
  if (method === 'GET' && u.pathname === '/challenges') {
    const uuid = u.searchParams.get('uuid');
    if (!uuid) { json(400, { error: 'uuid required' }); return; }
    const rows = db.prepare(`SELECT from_name, wave, kills, created_at FROM challenges WHERE to_uuid = ? AND status = 'pending' ORDER BY created_at DESC LIMIT 10`).all(uuid);
    json(200, { challenges: rows });
    return;
  }

  // GET /weekly_op
  if (method === 'GET' && u.pathname === '/weekly_op') {
    const op = ensureWeeklyOp();
    json(200, op);
    return;
  }

  // GET /daily_missions?date=YYYY-MM-DD
  if (method === 'GET' && u.pathname === '/daily_missions') {
    const date = u.searchParams.get('date') || new Date().toISOString().slice(0, 10);
    json(200, { missions: getDailyMissions(date), date });
    return;
  }

  // 404
  json(404, { error: 'not found' });
});

const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

/**
 * roomId → { players: Set<socketId>, hostId: string, readyCount: number, code: string }
 * @type {Map<string, {players: Set<string>, hostId: string, readyCount: number, code: string}>}
 */
const rooms = new Map();

/**
 * 5-char code → roomId  (only pending rooms awaiting a second player)
 * @type {Map<string, string>}
 */
const roomsByCode = new Map();

/**
 * roomId → creator's player name  (set on create_room, deleted on join_room/cancel)
 * @type {Map<string, string>}
 */
const pendingCreators = new Map();

/**
 * playerName → socket.id  (online presence registry)
 * @type {Map<string, string>}
 */
const onlinePlayers = new Map();

/**
 * socketId → { name: string, roomId: string, isHost: bool }  (per-connection info)
 * @type {Map<string, {name: string, roomId: string, isHost: boolean}>}
 */
const socketInfo = new Map();

/**
 * roomId → Map<playerName, { isHost: bool, timer: NodeJS.Timeout }>
 * Players who disconnected mid-game and are waiting to rejoin.
 */
const pendingRejoins = new Map();

function findRoomBySocket(socketId) {
  for (const [roomId, room] of rooms) {
    if (room.players.has(socketId)) return { roomId, room };
  }
  return null;
}

function generateRoomCode() {
  // Exclude chars that look alike: 0/O, 1/I
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code, attempts = 0;
  do {
    code = '';
    for (let i = 0; i < 5; i++) code += chars[Math.floor(Math.random() * chars.length)];
    attempts++;
  } while (roomsByCode.has(code) && attempts < 100);
  return code;
}

io.on('connection', (socket) => {
  console.log(`[+] ${socket.id} connected  (total: ${io.engine.clientsCount})`);

  // ── Online presence ────────────────────────────────────────────────────────

  socket.on('register_online', ({ player_name }) => {
    if (player_name) onlinePlayers.set(player_name, socket.id);
  });

  socket.on('check_friends_online', ({ friends }) => {
    if (!Array.isArray(friends)) return;
    const online_names = friends.filter(name => onlinePlayers.has(name));
    socket.emit('friends_online_status', { online_names });
  });

  socket.on('ping_friend', ({ target_name, from_name, room_code }) => {
    const targetId = onlinePlayers.get(target_name);
    if (targetId) {
      io.to(targetId).emit('friend_invite', { from_name, room_code });
      console.log(`[invite] ${from_name} → ${target_name} (code=${room_code})`);
    }
  });

  // ── Matchmaking (room codes) ───────────────────────────────────────────────

  socket.on('create_room', ({ player_name }) => {
    const code   = generateRoomCode();
    const roomId = `room_${Date.now()}_${Math.floor(Math.random() * 9999)}`;
    const room   = { players: new Set([socket.id]), hostId: socket.id, readyCount: 0, code, gameStarted: false };
    rooms.set(roomId, room);
    roomsByCode.set(code, roomId);
    pendingCreators.set(roomId, player_name);
    socketInfo.set(socket.id, { name: player_name, roomId, isHost: true });
    socket.join(roomId);
    socket.emit('room_created', { code, room_id: roomId });
    console.log(`[room] ${roomId}: created by ${player_name} code=${code}`);
  });

  socket.on('join_room', ({ code, player_name }) => {
    const upperCode = (code || '').trim().toUpperCase();
    const roomId    = roomsByCode.get(upperCode);
    if (!roomId) {
      socket.emit('join_error', { message: 'Room not found' });
      return;
    }
    const room = rooms.get(roomId);
    if (!room || room.players.size >= 2) {
      socket.emit('join_error', { message: 'Room is full' });
      return;
    }
    const hostName = pendingCreators.get(roomId) || 'UNKNOWN';
    room.players.add(socket.id);
    roomsByCode.delete(upperCode);
    pendingCreators.delete(roomId);
    socket.join(roomId);
    socketInfo.set(socket.id, { name: player_name, roomId, isHost: false });
    // Update host's socketInfo with the room
    for (const [sid, info] of socketInfo) {
      if (sid !== socket.id && info.roomId === roomId) {
        info.name = pendingCreators.get(roomId) || info.name || 'HOST';
      }
    }
    socket.emit('match_found', { room_id: roomId, partner_name: hostName,  is_host: false });
    io.to(room.hostId).emit('match_found', { room_id: roomId, partner_name: player_name, is_host: true });
    console.log(`[room] ${roomId}: ${player_name} joined host, code=${upperCode}`);
  });

  socket.on('cancel_room', () => {
    const result = findRoomBySocket(socket.id);
    if (result) {
      const { roomId, room } = result;
      if (room.code) roomsByCode.delete(room.code);
      pendingCreators.delete(roomId);
      rooms.delete(roomId);
      console.log(`[room] ${roomId}: cancelled by creator`);
    }
  });

  socket.on('player_ready', ({ room_id }) => {
    const room = rooms.get(room_id);
    if (!room) return;
    room.readyCount += 1;
    socket.to(room_id).emit('partner_ready', {});
    if (room.readyCount >= 2) {
      room.gameStarted = true;
      io.to(room_id).emit('game_start', {});
      console.log(`[room] ${room_id}: game started`);
    }
  });

  // ── Reconnect (mid-game socket drop) ──────────────────────────────────────

  socket.on('rejoin_room', ({ room_id, player_name, is_host }) => {
    const room = rooms.get(room_id);
    const pending = pendingRejoins.get(room_id);
    if (!room || !pending || !pending.has(player_name)) {
      socket.emit('rejoin_error', { message: 'Room not found or reconnect window expired' });
      console.log(`[room] ${room_id}: rejoin rejected for ${player_name}`);
      return;
    }
    const info = pending.get(player_name);
    clearTimeout(info.timer);
    pending.delete(player_name);
    if (pending.size === 0) pendingRejoins.delete(room_id);

    // Restore player into room
    room.players.add(socket.id);
    if (info.isHost) room.hostId = socket.id;
    socket.join(room_id);
    socketInfo.set(socket.id, { name: player_name, roomId: room_id, isHost: info.isHost });
    onlinePlayers.set(player_name, socket.id);

    socket.emit('rejoin_confirmed', { room_id, is_host: info.isHost });
    socket.to(room_id).emit('partner_reconnected', {});
    console.log(`[room] ${room_id}: ${player_name} rejoined (isHost=${info.isHost})`);
  });

  // ── In-game relay (no game logic on the server) ────────────────────────────

  // Real-time player position/animation
  socket.on('player_state', (data) => {
    socket.to(data.room_id).emit('remote_player_state', data);
  });

  // Visual bullet relay (partner sees bullets being fired)
  socket.on('bullet_fired', (data) => {
    socket.to(data.room_id).emit('remote_bullet_fired', data);
  });

  // Partner died → tell other player
  socket.on('player_died', ({ room_id }) => {
    socket.to(room_id).emit('partner_died', {});
    console.log(`[room] ${room_id}: a player died`);
  });

  // ── Enemy sync (host spawns, broadcasts to client) ─────────────────────────

  socket.on('enemy_spawned', (data) => {
    socket.to(data.room_id).emit('remote_enemy_spawned', data);
  });

  socket.on('enemies_sync', (data) => {
    socket.to(data.room_id).emit('remote_enemies_sync', data);
  });

  // Either player killed an enemy — relay to the other
  socket.on('enemy_killed', (data) => {
    socket.to(data.room_id).emit('remote_enemy_killed', data);
  });

  // Client hit an enemy → forward to host for authoritative kill resolution
  socket.on('enemy_hit', (data) => {
    const result = findRoomBySocket(socket.id);
    if (result) {
      const { room } = result;
      if (room.hostId !== socket.id) {
        // Only relay client → host direction
        io.to(room.hostId).emit('remote_enemy_hit', data);
      }
    }
  });

  // ── Wave / build phase events ──────────────────────────────────────────────

  // Host broadcasts wave lifecycle events to client
  socket.on('wave_event', (data) => {
    // Reset build ready votes when a new wave starts
    if (data.type === 'wave_start') {
      const room = rooms.get(data.room_id);
      if (room) room.buildReadyVotes = 0;
    }
    socket.to(data.room_id).emit('remote_wave_event', data);
  });

  // Build-phase early-end: both players vote → server triggers build_end on both
  socket.on('build_ready_vote', ({ room_id }) => {
    const room = rooms.get(room_id);
    if (!room) return;
    room.buildReadyVotes = (room.buildReadyVotes || 0) + 1;
    // Tell the OTHER player how many votes so they can show "partner is ready"
    socket.to(room_id).emit('remote_build_ready_vote', { votes: room.buildReadyVotes });
    console.log(`[room] ${room_id}: build_ready_vote ${room.buildReadyVotes}/2`);
    if (room.buildReadyVotes >= 2) {
      room.buildReadyVotes = 0;
      io.to(room_id).emit('remote_build_end_vote', {});
      console.log(`[room] ${room_id}: both voted ready — ending build phase`);
    }
  });

  // ── Structure sync ─────────────────────────────────────────────────────────

  socket.on('structure_placed', (data) => {
    socket.to(data.room_id).emit('remote_structure_placed', data);
  });

  socket.on('structure_erased', (data) => {
    socket.to(data.room_id).emit('remote_structure_erased', data);
  });

  socket.on('door_toggled', (data) => {
    socket.to(data.room_id).emit('remote_door_toggled', data);
  });

  // ── Score sync (host → client) ─────────────────────────────────────────────

  socket.on('score_sync', (data) => {
    socket.to(data.room_id).emit('remote_score_sync', data);
  });

  // ── Support abilities (squad / airstrike) ──────────────────────────────────

  // Relay squad spawn to partner so they see the soldiers too
  socket.on('squad_spawned', (data) => {
    socket.to(data.room_id).emit('remote_squad_spawned', data);
  });

  // Relay airstrike so partner sees the visual + takes the damage
  socket.on('airstrike_used', (data) => {
    socket.to(data.room_id).emit('remote_airstrike_used', data);
  });

  // ── Coin deduplication ───────────────────────────────────────────────────────
  // Tell partner a coin was collected so they remove their local copy.
  socket.on('coin_collected', (data) => {
    socket.to(data.room_id).emit('remote_coin_collected', data);
  });

  // ── Revive mechanic ──────────────────────────────────────────────────────────
  socket.on('player_downed', (data) => {
    socket.to(data.room_id).emit('remote_player_downed', data);
  });

  socket.on('player_revived', (data) => {
    socket.to(data.room_id).emit('remote_player_revived', data);
  });

  // ── Game over sync ───────────────────────────────────────────────────────────
  // Carries kills count so the game-over screen can show both players' stats.
  socket.on('game_over_sync', (data) => {
    socket.to(data.room_id).emit('remote_game_over_sync', data);
  });

  // ── Disconnect ────────────────────────────────────────────────────────────

  socket.on('disconnect', () => {
    console.log(`[-] ${socket.id} disconnected`);
    const info = socketInfo.get(socket.id);
    socketInfo.delete(socket.id);
    // Remove from presence registry
    for (const [name, id] of onlinePlayers) {
      if (id === socket.id) { onlinePlayers.delete(name); break; }
    }
    const result = findRoomBySocket(socket.id);
    if (!result) return;
    const { roomId, room } = result;
    room.players.delete(socket.id);

    if (!room.gameStarted) {
      // Pre-game: clean up immediately
      if (room.code) roomsByCode.delete(room.code);
      pendingCreators.delete(roomId);
      if (room.players.size > 0) socket.to(roomId).emit('partner_disconnected', {});
      rooms.delete(roomId);
      console.log(`[room] ${roomId}: closed before game started`);
      return;
    }

    if (room.players.size === 0) {
      // Both gone — clean up
      rooms.delete(roomId);
      pendingRejoins.delete(roomId);
      console.log(`[room] ${roomId}: all players gone, closed`);
      return;
    }

    // Game was active: give this player 60s to reconnect
    const playerName = info ? info.name : '?';
    const isHost     = info ? info.isHost : (socket.id === room.hostId);
    socket.to(roomId).emit('partner_disconnected', {});

    const timer = setTimeout(() => {
      // Grace period expired — tell remaining player it's truly over
      const pending = pendingRejoins.get(roomId);
      if (pending) { pending.delete(playerName); if (pending.size === 0) pendingRejoins.delete(roomId); }
      io.to(roomId).emit('partner_reconnect_failed', {});
      // Clean up room if empty after notification
      if (room.players.size === 0) rooms.delete(roomId);
      console.log(`[room] ${roomId}: ${playerName} reconnect window expired`);
    }, 60000);

    if (!pendingRejoins.has(roomId)) pendingRejoins.set(roomId, new Map());
    pendingRejoins.get(roomId).set(playerName, { isHost, timer });
    console.log(`[room] ${roomId}: ${playerName} disconnected mid-game, 60s reconnect window`);
  });
});

const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, () => {
  console.log(`Resistance co-op server listening on port ${PORT}`);
  console.log(`Update SERVER_URL in scripts/network_manager.gd to point here.`);
});
