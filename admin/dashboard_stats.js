/* ══════════════════════════════════════════════════════════
   PolaMove Admin — Dashboard statistics
   ──────────────────────────────────────────────────────────
   Computes the four stat cards on the Dashboard from live
   Firestore data and writes them into the existing markup.
   No new collections, no second Firebase init — the caller
   passes in the `db` created by polamove_admin_firebase.js.

   Read budget: this module adds ONE listener (today's rides)
   plus one one-shot read for yesterday's totals. Drivers,
   passengers and active-ride counts are fed in from the
   listeners polamove_admin_firebase.js already runs.
   ══════════════════════════════════════════════════════════ */

import {
  collection, query, where, onSnapshot, getDocs, Timestamp
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js';

/* The Philippines is UTC+8 all year — no DST — so a fixed offset is exact.
   The console may be opened from a browser in another timezone; "today"
   must still mean today in Polangui, not today where the admin is sitting. */
const PH_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS       = 24 * 60 * 60 * 1000;

/* Status flow from lib/core/services/ride_service.dart:
     searching → accepted → arrived → ongoing → completed,
     or cancelled from any pre-completed state.
   Anything before completed/cancelled is a ride still in progress. */
const ACTIVE_RIDE_STATUSES = ['searching', 'accepted', 'arrived', 'ongoing'];

/* Headline number for the Active Drivers card. Approved AND online — so the
   card reacts the moment a driver toggles their online switch. Flip this to
   `online + offline` if you'd rather the headline count every approved driver. */
const driversHeadline = (online, _offline) => online;

/* ── STATE ─────────────────────────────────────────────────
   null means "not loaded yet" and renders as a loading state.
   Never render a number we haven't actually read from Firestore. */
const stats = {
  driversOnline:   null,
  driversOffline:  null,
  passengers:      null,
  passengersToday: null,
  activeRidesNow:  null,
  tripsToday:      null,
  tripsCompleted:  null,
  tripsActive:     null,
  revenueToday:    null,
  rideTypes:       null,   // { solo, share, total } for the Ride Type Split
  topRoutes:       null,   // [{ label, count }] sorted desc, max 5
  tripsYesterday:   null,   // trend baseline; stays null if the read fails
  revenueYesterday: null,
};

const errors = { drivers: null, passengers: null, rides: null, today: null };

let unsubToday    = null;
let rolloverTimer = null;
let started       = false;

/* ── DAY BOUNDARIES (Philippines) ──────────────────────────
   Shift the instant by +8h, read its UTC calendar date, then shift the
   resulting midnight back. Works no matter what timezone the browser is in. */
function phDayStart(date) {
  const shifted = new Date(date.getTime() + PH_OFFSET_MS);
  const midnightShifted = Date.UTC(
    shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()
  );
  return new Date(midnightShifted - PH_OFFSET_MS);
}

/* ══ LIFECYCLE ═════════════════════════════════════════════ */

/** Attaches the today-rides listener. Safe to call twice. */
export function startDashboardStats(db) {
  if (started) return;
  started = true;
  render();                 // paint the loading state immediately
  watchToday(db);
}

/** Detaches everything. Called on sign-out. */
export function stopDashboardStats() {
  if (unsubToday) { unsubToday(); unsubToday = null; }
  clearTimeout(rolloverTimer);
  rolloverTimer = null;
  started = false;

  Object.keys(stats).forEach(k => { stats[k] = null; });
  Object.keys(errors).forEach(k => { errors[k] = null; });

  // Back to the loading state, so the next admin to sign in never sees the
  // previous session's numbers while the listeners warm up.
  render();
}

function watchToday(db) {
  const start = phDayStart(new Date());
  const end   = new Date(start.getTime() + DAY_MS);

  /* Range filter on a single field — served by the automatic index,
     no composite index needed. */
  unsubToday = onSnapshot(
    query(
      collection(db, 'rides'),
      where('requestedAt', '>=', Timestamp.fromDate(start)),
      where('requestedAt', '<',  Timestamp.fromDate(end)),
    ),
    snap => {
      let trips = 0, completed = 0, active = 0, revenue = 0;
      const typeCounts  = new Map();
      const routeCounts = new Map();

      snap.forEach(d => {
        const v = d.data();
        trips += 1;

        if (v.status === 'completed') {
          completed += 1;
          revenue   += Number(v.totalFare) || 0;   // totalFare, never baseFare
        } else if (ACTIVE_RIDE_STATUSES.includes(v.status)) {
          active += 1;                             // cancelled counts as neither
        }

        /* Ride Type Split and Top Routes describe demand — every ride
           requested today, matching the Trips Today headline exactly, so the
           donut is a breakdown of the number on the card above it. */
        const type = text(v.rideType, 'Unknown');
        typeCounts.set(type, (typeCounts.get(type) || 0) + 1);

        const from = text(v.pickup?.name,  'Unknown Pickup');
        const to   = text(v.dropoff?.name, 'Unknown Destination');
        const route = `${from} → ${to}`;
        routeCounts.set(route, (routeCounts.get(route) || 0) + 1);
      });

      errors.today        = null;
      stats.tripsToday    = trips;
      stats.tripsCompleted= completed;
      stats.tripsActive   = active;
      stats.revenueToday  = revenue;

      stats.rideTypes = {
        solo:  typeCounts.get('PolaSolo')  || 0,
        share: typeCounts.get('PolaShare') || 0,
        rent:  typeCounts.get('PolaRent')  || 0,
        total: trips,
      };

      // Busiest first; ties broken alphabetically so the order doesn't jitter
      // between snapshots.
      stats.topRoutes = [...routeCounts.entries()]
        .map(([label, count]) => ({ label, count }))
        .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
        .slice(0, 5);

      render();
    },
    err => {
      console.warn('dashboard today-rides listener:', err.message);
      errors.today = err;
      render();
    },
  );

  loadYesterday(db, start);
  scheduleRollover(db, end);
}

/** Yesterday is closed — a one-shot read is enough, and it only feeds trends. */
async function loadYesterday(db, todayStart) {
  const start = new Date(todayStart.getTime() - DAY_MS);

  try {
    const snap = await getDocs(query(
      collection(db, 'rides'),
      where('requestedAt', '>=', Timestamp.fromDate(start)),
      where('requestedAt', '<',  Timestamp.fromDate(todayStart)),
    ));

    let trips = 0, revenue = 0;
    snap.forEach(d => {
      const v = d.data();
      trips += 1;
      if (v.status === 'completed') revenue += Number(v.totalFare) || 0;
    });

    stats.tripsYesterday   = trips;
    stats.revenueYesterday = revenue;
    render();
  } catch (e) {
    // Trends are optional garnish — a failure here hides the pill, nothing more.
    console.warn('dashboard yesterday totals:', e.message);
  }
}

/** Re-scopes the listener when the Philippine day rolls over. */
function scheduleRollover(db, end) {
  clearTimeout(rolloverTimer);
  const wait = end.getTime() - Date.now() + 2000;   // small cushion past midnight
  rolloverTimer = setTimeout(() => {
    if (unsubToday) { unsubToday(); unsubToday = null; }
    stats.tripsToday = stats.tripsCompleted = stats.tripsActive = null;
    stats.revenueToday = null;
    stats.rideTypes = stats.topRoutes = null;
    watchToday(db);
  }, wait);
}

/* ══ FEEDS ═════════════════════════════════════════════════
   Called from the listeners polamove_admin_firebase.js already owns,
   so these cost no extra Firestore reads. */

/** drivers/{uid} — approved + online is what "active" means here. */
export function applyDriversSnapshot(snap) {
  let online = 0, offline = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.status !== 'approved') return;      // pending / rejected are not active
    if (v.isOnline === true) online += 1;
    else offline += 1;
  });

  errors.drivers      = null;
  stats.driversOnline = online;
  stats.driversOffline= offline;
  render();
}

/** users/{uid} with role === 'passenger'. There is no /passengers collection. */
export function applyUsersSnapshot(snap) {
  const dayStart = phDayStart(new Date()).getTime();
  let total = 0, today = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.role !== 'passenger') return;
    total += 1;

    const created = v.createdAt?.toDate?.();
    if (created && created.getTime() >= dayStart) today += 1;
  });

  errors.passengers     = null;
  stats.passengers      = total;
  stats.passengersToday = today;
  render();
}

/** Rides in progress right now, from the existing recent-rides listener. */
export function applyActiveRidesNow(count) {
  errors.rides         = null;
  stats.activeRidesNow = count;
  render();
}

/** kind: 'drivers' | 'passengers' | 'rides' */
export function reportDashboardError(kind, err) {
  errors[kind] = err;
  render();
}

/* ══ RENDER ════════════════════════════════════════════════
   Writes into the existing card markup only — no elements created,
   no styles changed beyond the up/dn classes the CSS already defines. */

const CARDS = {
  drivers:    { val: 's-drivers',    sub: 's-drivers-sub',    trend: 's-drivers-trend'    },
  passengers: { val: 's-passengers', sub: 's-passengers-sub', trend: 's-passengers-trend' },
  trips:      { val: 's-trips',      sub: 's-trips-sub',      trend: 's-trips-trend'      },
  revenue:    { val: 's-revenue',    sub: 's-revenue-sub',    trend: 's-revenue-trend'    },
};

const el = id => document.getElementById(id);

/** Matches the ₱480 / ₱2,840 formatting already used across the console. */
function peso(amount) {
  const n = Math.round((Number(amount) || 0) * 100) / 100;
  return '₱' + n.toLocaleString('en-PH', {
    minimumFractionDigits: Number.isInteger(n) ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

/** Trimmed string or a fallback — guards against missing/non-string fields. */
function text(value, fallback) {
  return (typeof value === 'string' && value.trim()) ? value.trim() : fallback;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function errorText(err) {
  const code = err?.code || '';
  if (code.includes('permission-denied'))  return 'No permission to read this data';
  if (code.includes('unavailable') ||
      code.includes('network'))            return 'Offline — cannot reach Firebase';
  if (code.includes('failed-precondition'))return 'Firestore index still building';
  return 'Live data unavailable';
}

function paint(card, { value, sub, trend = null, dir = 'up', isError = false }) {
  const v = el(card.val), s = el(card.sub), t = el(card.trend);

  if (v) v.textContent = value;
  if (s) {
    s.textContent = sub;
    s.classList.toggle('err', isError);
  }
  if (t) {
    if (trend === null) {
      t.style.display = 'none';
    } else {
      t.style.display = '';
      t.className     = 'sc-trend ' + dir;
      t.textContent   = trend;
    }
  }
}

/** Trend pill against yesterday. Hidden when there's no baseline or no change —
    an invented arrow is worse than no arrow. */
function dayTrend(todayVal, yesterdayVal, format) {
  if (todayVal === null || yesterdayVal === null) return null;
  const diff = todayVal - yesterdayVal;
  if (diff === 0) return null;
  return {
    trend: `${diff > 0 ? '↑' : '↓'} ${format(Math.abs(diff))} vs yest.`,
    dir:   diff > 0 ? 'up' : 'dn',
  };
}

function render() {
  renderDrivers();
  renderPassengers();
  renderTrips();
  renderRevenue();
  renderRideTypeSplit();
  renderTopRoutes();
}

/* ── Ride Type Split ───────────────────────────────────────
   Drives the two arcs of the existing SVG donut. r=28 in that
   markup, so the full circle is 2πr long. */
const DONUT_C = 2 * Math.PI * 28;

function setArc(arc, length, offset) {
  if (!arc) return;
  arc.setAttribute('stroke-dasharray', `${length} ${DONUT_C - length}`);
  arc.setAttribute('stroke-dashoffset', String(offset));
}

function renderRideTypeSplit() {
  const solo = el('rt-arc-solo'), share = el('rt-arc-share'), rent = el('rt-arc-rent');
  const centre = el('rt-center');
  const soloVal = el('rt-solo-val'), shareVal = el('rt-share-val'), rentVal = el('rt-rent-val');

  const paintSplit = (soloLen, shareLen, rentLen, soloTxt, shareTxt, rentTxt) => {
    setArc(solo, soloLen, 0);
    setArc(share, shareLen, -soloLen);                 // share starts where solo ends
    setArc(rent, rentLen, -(soloLen + shareLen));      // rent picks up after share
    if (centre)   centre.textContent   = soloTxt;
    if (soloVal)  soloVal.textContent  = soloTxt;
    if (shareVal) shareVal.textContent = shareTxt;
    if (rentVal)  rentVal.textContent  = rentTxt;
  };

  // Loading or failed — empty ring, no numbers.
  if (errors.today || stats.rideTypes === null) return paintSplit(0, 0, 0, '—', '—', '—');

  const { solo: soloCount, share: shareCount, rent: rentCount, total } = stats.rideTypes;

  // No rides today: 0% across the board, and never a division by zero.
  if (!total) return paintSplit(0, 0, 0, '0%', '0%', '0%');

  const soloPct  = soloCount  / total;
  const sharePct = shareCount / total;
  const rentPct  = rentCount  / total;

  /* The app only ever writes PolaSolo/PolaShare/PolaRent, so these three
     cover every ride and the labels total 100%. The last slice takes the
     remainder rather than its own rounding, so 33/33/33 never reads 99%. */
  const soloLabel  = Math.round(soloPct  * 100);
  const shareLabel = Math.round(sharePct * 100);
  const rentLabel  = rentCount ? 100 - soloLabel - shareLabel : 0;

  paintSplit(
    DONUT_C * soloPct,
    DONUT_C * sharePct,
    DONUT_C * rentPct,
    soloLabel  + '%',
    shareLabel + '%',
    rentLabel  + '%',
  );
}

/* ── Top Routes Today ──────────────────────────────────────
   Bar widths are relative to the busiest route, which is
   topRoutes[0] because the list is already sorted desc. */
function renderTopRoutes() {
  const box = el('top-routes-chart');
  if (!box) return;

  if (errors.today)
    return void (box.innerHTML = chartState('⚠️', 'Unable to load top routes'));
  if (stats.topRoutes === null)
    return void (box.innerHTML = chartState('⏳', 'Loading top routes…'));
  if (!stats.topRoutes.length)
    return void (box.innerHTML = chartState('🗺️', 'No rides today'));

  const max = stats.topRoutes[0].count;    // ≥ 1, so the division is always safe
  const last = stats.topRoutes.length - 1;

  box.innerHTML = stats.topRoutes.map((r, i) => `
    <div class="bar-row">
      <div class="bar-lbl" title="${escapeHtml(r.label)}">${escapeHtml(r.label)}</div>
      <div class="bar-track"><div class="bar-fill${i === last ? ' grn' : ''}" style="width:${(r.count / max * 100).toFixed(2)}%"></div></div>
      <div class="bar-val">${r.count}</div>
    </div>`).join('');
}

function chartState(icon, title) {
  return `<div class="empty-state"><div class="es-icon">${icon}</div><div class="es-title">${title}</div></div>`;
}

/* Lets the dashboard view re-paint both charts on navigation — the classic
   script in index.html can't import from this module. */
window.renderDashboardCharts = function () {
  renderRideTypeSplit();
  renderTopRoutes();
};

function renderDrivers() {
  if (errors.drivers) {
    return paint(CARDS.drivers, { value: '—', sub: errorText(errors.drivers), isError: true });
  }
  if (stats.driversOnline === null) {
    return paint(CARDS.drivers, { value: '…', sub: 'Loading…' });
  }

  const { driversOnline: on, driversOffline: off } = stats;
  paint(CARDS.drivers, {
    value: String(driversHeadline(on, off)),
    sub:   (on + off) === 0
             ? 'No approved drivers yet'
             : `${on} online · ${off} offline`,
  });
}

function renderPassengers() {
  if (errors.passengers) {
    return paint(CARDS.passengers, { value: '—', sub: errorText(errors.passengers), isError: true });
  }
  if (stats.passengers === null) {
    return paint(CARDS.passengers, { value: '…', sub: 'Loading…' });
  }

  let sub;
  if (errors.rides)                     sub = 'Active rides unavailable';
  else if (stats.activeRidesNow === null) sub = 'Checking active rides…';
  else if (stats.activeRidesNow === 0)  sub = 'No active rides now';
  else sub = `${stats.activeRidesNow} active ride${stats.activeRidesNow === 1 ? '' : 's'} now`;

  const newToday = stats.passengersToday;
  paint(CARDS.passengers, {
    value: String(stats.passengers),
    sub,
    trend: newToday ? `↑ ${newToday} today` : null,
  });
}

function renderTrips() {
  if (errors.today) {
    return paint(CARDS.trips, { value: '—', sub: errorText(errors.today), isError: true });
  }
  if (stats.tripsToday === null) {
    return paint(CARDS.trips, { value: '…', sub: 'Loading…' });
  }

  const t = dayTrend(stats.tripsToday, stats.tripsYesterday, n => String(n));
  paint(CARDS.trips, {
    value: String(stats.tripsToday),
    sub:   stats.tripsToday === 0
             ? 'No trips yet today'
             : `${stats.tripsCompleted} completed · ${stats.tripsActive} active`,
    trend: t?.trend ?? null,
    dir:   t?.dir ?? 'up',
  });
}

function renderRevenue() {
  if (errors.today) {
    return paint(CARDS.revenue, { value: '—', sub: errorText(errors.today), isError: true });
  }
  if (stats.revenueToday === null) {
    return paint(CARDS.revenue, { value: '…', sub: 'Loading…' });
  }

  const t = dayTrend(stats.revenueToday, stats.revenueYesterday, peso);
  paint(CARDS.revenue, {
    value: peso(stats.revenueToday),
    sub:   stats.tripsCompleted === 0
             ? 'No completed trips yet'
             : 'Cash · No digital payment',
    trend: t?.trend ?? null,
    dir:   t?.dir ?? 'up',
  });
}