'use strict';

const http   = require('http');
const { Server } = require('socket.io');

const server = http.createServer();
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
