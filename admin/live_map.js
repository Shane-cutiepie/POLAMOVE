/* ══════════════════════════════════════════════════════════
   PolaMove Admin — Live Ride Monitoring
   ──────────────────────────────────────────────────────────
   Plots the driver of every in-progress ride on the existing
   Leaflet map. No new collections: active rides come from
   /rides, positions from drivers/{uid}.location.

   Read budget: ONE listener, scoped to active rides only.
   Driver documents are NOT listened to per-driver here — the
   admin console already streams the whole /drivers collection
   for the registry table, so those positions arrive for free.
   A per-driver listener would re-read documents we already
   have. polamove_admin_firebase.js feeds them in via
   applyLiveMapDrivers().
   ══════════════════════════════════════════════════════════ */

import {
  collection, query, where, onSnapshot
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js';

/* Status flow in lib/core/services/ride_service.dart:
     searching → accepted → arrived → ongoing → completed | cancelled
   Only these three have a driver attached, so only these can be plotted.
   `searching` is still an active ride but has driverId == null — there is
   no position to draw. completed/cancelled are never shown. */
const PLOTTABLE_RIDE_STATUSES = ['accepted', 'arrived', 'ongoing'];

const RIDE_STATUS_LABELS = {
  accepted: 'Accepted',
  arrived:  'Arrived',
  ongoing:  'Ongoing',
};

/* ── STATE ─────────────────────────────────────────────── */
let unsubRides  = null;
let started     = false;
let ridesLoaded = false;
let error       = null;

let activeRides = [];          // [{ id, driverId, status, type, from, to }]
let drivers     = new Map();   // uid → { name, status, isOnline, lat, lng, approximate, updatedAt }
const markers   = new Map();   // rideId → L.Marker

/* ══ LIFECYCLE ═════════════════════════════════════════════ */

export function startLiveMap(db) {
  if (started) return;
  started = true;

  // Single-field `in` filter — served by the automatic index, no composite
  // index required, and it reads only rides currently in progress.
  unsubRides = onSnapshot(
    query(collection(db, 'rides'), where('status', 'in', PLOTTABLE_RIDE_STATUSES)),
    snap => {
      activeRides = [];

      snap.forEach(d => {
        const v = d.data();
        if (!v.driverId) return;            // not matched yet — nothing to plot

        activeRides.push({
          id:       d.id,
          driverId: v.driverId,
          status:   v.status,
          type:     text(v.rideType, 'Unknown type'),
          from:     text(v.pickup?.name,  'Unknown Pickup'),
          to:       text(v.dropoff?.name, 'Unknown Destination'),
        });
      });

      ridesLoaded = true;
      error = null;
      renderMarkers();
    },
    err => {
      console.warn('live map rides listener:', err.message);
      error = err;
      renderMarkers();
    },
  );
}

export function stopLiveMap() {
  if (unsubRides) { unsubRides(); unsubRides = null; }

  const map = leafletMap();
  markers.forEach(m => { if (map) map.removeLayer(m); });
  markers.clear();

  activeRides = [];
  drivers     = new Map();
  ridesLoaded = false;
  error       = null;
  started     = false;
  renderMarkers();
}

/**
 * Driver positions, fed from the /drivers snapshot the console already runs.
 * directory: Map(uid → { name, status, isOnline, lat, lng, approximate, updatedAt })
 */
export function applyLiveMapDrivers(directory) {
  drivers = directory instanceof Map ? directory : new Map();
  renderMarkers();
}

export function reportLiveMapError(err) {
  error = err;
  renderMarkers();
}

/* ══ MARKERS ═══════════════════════════════════════════════ */

/** The Leaflet instance created by initAdmMap() in index.html. */
function leafletMap() {
  return (typeof admMap !== 'undefined' && admMap) ? admMap : null;
}

function renderMarkers() {
  const map = leafletMap();
  if (!map) return;        // Leaflet not up yet — initAdmMap() calls back

  const live = new Set();
  let plotted = 0, unlocatable = 0;

  if (!error) {
    for (const ride of activeRides) {
      const d = drivers.get(ride.driverId);

      /* A driver is only shown as live if they are approved, online, and have
         a stored position. Going offline clears drivers/{uid}.location in
         LocationService.clearLocation(), so an offline driver has nothing to
         draw anyway. A deleted or unapproved driver is skipped, not crashed. */
      if (!d || d.status !== 'approved' || !d.isOnline ||
          d.lat === null || d.lng === null) {
        unlocatable += 1;
        continue;
      }

      live.add(ride.id);
      plotted += 1;
      upsertMarker(map, ride, d);
    }
  }

  /* Rides that completed, were cancelled, or lost their driver drop off the
     map. Only these layers are touched — the map itself is never rebuilt. */
  markers.forEach((marker, rideId) => {
    if (!live.has(rideId)) {
      map.removeLayer(marker);
      markers.delete(rideId);
    }
  });

  updateStatus(plotted, unlocatable);
}

function upsertMarker(map, ride, d) {
  const popup = popupHtml(ride, d);
  const existing = markers.get(ride.id);

  if (existing) {
    // Move the marker in place rather than recreating it, so the map never
    // flickers and the popup stays open while the driver drives.
    const at = existing.getLatLng();
    if (at.lat !== d.lat || at.lng !== d.lng) existing.setLatLng([d.lat, d.lng]);
    existing.setPopupContent(popup);
    return;
  }

  // Same divIcon treatment the demo markers used for an in-progress ride.
  const icon = L.divIcon({
    html: '<div style="font-size:18px;filter:drop-shadow(0 2px 6px rgba(0,0,0,.5))">🔴</div>',
    iconAnchor: [9, 18],
    className: '',
  });

  markers.set(ride.id, L.marker([d.lat, d.lng], { icon }).addTo(map).bindPopup(popup));
}

/* Admin-facing ride detail only. Passenger identity is deliberately left out —
   the live map doesn't need it. */
function popupHtml(ride, d) {
  const label = RIDE_STATUS_LABELS[ride.status] || ride.status || 'Unknown';
  return `<b>${esc(d.name)}</b><br>`
       + `${esc(ride.from)} → ${esc(ride.to)}<br>`
       + `${esc(ride.type)} · <b>${esc(label)}</b><br>`
       + `<span style="opacity:.75">${d.approximate ? 'Approximate location' : 'GPS location'}`
       + ` · ${esc(relativeTime(d.updatedAt))}</span>`;
}

/* ══ STATUS LINE ═══════════════════════════════════════════
   The map always stays visible; this only reports what isn't on it. */
function updateStatus(plotted, unlocatable) {
  const box = document.getElementById('map-status');
  if (!box) return;

  const show = msg => {
    box.textContent = msg;
    box.classList.add('show');
  };

  if (error)        return show('Unable to load active rides');
  if (!ridesLoaded) return show('Loading active rides…');

  const stranded = unlocatable === 1
    ? '1 active ride has no driver location'
    : `${unlocatable} active rides have no driver location`;

  if (plotted === 0 && unlocatable === 0) return show('No active rides');
  if (plotted === 0)                      return show(stranded);
  if (unlocatable > 0)                    return show(stranded);

  box.classList.remove('show');
}

/* ══ HELPERS ═══════════════════════════════════════════════ */

function text(value, fallback) {
  return (typeof value === 'string' && value.trim()) ? value.trim() : fallback;
}

function esc(s) {
  return String(s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/* The app defines no stale-location timeout — LocationService just writes the
   latest fix — so nothing is hidden for being old. The age is surfaced in the
   popup instead, and the admin can judge it. */
function relativeTime(date) {
  if (!date) return 'update time unknown';

  const secs = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
  if (secs < 60) return 'updated just now';

  const mins = Math.round(secs / 60);
  if (mins < 60) return `updated ${mins} minute${mins === 1 ? '' : 's'} ago`;

  const hours = Math.round(mins / 60);
  if (hours < 24) return `updated ${hours} hour${hours === 1 ? '' : 's'} ago`;

  const days = Math.round(hours / 24);
  return `updated ${days} day${days === 1 ? '' : 's'} ago`;
}

/* initAdmMap() calls this once Leaflet exists, so markers appear even when the
   snapshots landed before the map was built. */
window.renderLiveMap = renderMarkers;