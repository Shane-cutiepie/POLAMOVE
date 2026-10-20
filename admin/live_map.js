/* ══════════════════════════════════════════════════════════
   PolaMove Admin — Live Ride Monitoring
   ──────────────────────────────────────────────────────────
   Plots the driver of every in-progress ride on the existing
   Google map. No new collections: active rides come from
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

const ACTIVE_RIDE_STATUSES = ['searching', 'accepted', 'arrived', 'ongoing'];

const RIDE_STATUS_LABELS = {
  searching: 'Searching for driver',
  accepted:  'Accepted',
  arrived:  'Arrived',
  ongoing:   'Ongoing',
};

const LOCATION_MAX_AGE_MS = 2 * 60 * 1000;
const LOCATION_FUTURE_TOLERANCE_MS = 30 * 1000;

let unsubRides  = null;
let started     = false;
let ridesLoaded = false;
let ridesError  = null;
let driversError = null;
let hasAutoFitted = false;

let activeRides = [];
let drivers     = new Map();
const markers   = new Map();

/* ══ LIFECYCLE ═════════════════════════════════════════════ */

export function startLiveMap(db) {
  if (started) return;
  started = true;

  unsubRides = onSnapshot(
    query(collection(db, 'rides'), where('status', 'in', ACTIVE_RIDE_STATUSES)),
    snap => {
      activeRides = [];

      snap.forEach(d => {
        const v = d.data();
        activeRides.push({
          id:       d.id,
          driverId: text(v.driverId, ''),
          status:   v.status,
          type:     text(v.rideType, 'Unknown type'),
          from:     text(v.pickup?.name,  'Unknown Pickup'),
          to:       text(v.dropoff?.name, 'Unknown Destination'),
          pickup:   coordinates(v.pickup?.location),
          dropoff:  coordinates(v.dropoff?.location),
        });
      });

      ridesLoaded = true;
      ridesError = null;
      renderMarkers();
    },
    err => {
      console.warn('live map rides listener:', err.message);
      ridesError = err;
      renderMarkers();
    },
  );
}

export function stopLiveMap() {
  if (unsubRides) { unsubRides(); unsubRides = null; }

  markers.forEach(({ marker, infoWindow }) => {
    Object.values(marker).forEach(item => item?.setMap(null));
    infoWindow.close();
  });
  markers.clear();

  activeRides = [];
  drivers     = new Map();
  ridesLoaded = false;
  ridesError = null;
  driversError = null;
  hasAutoFitted = false;
  started     = false;
  renderMarkers();
}

/**
 * Driver positions, fed from the /drivers snapshot the console already runs.
 * directory: Map(uid → { name, status, isOnline, lat, lng, approximate, updatedAt })
 */
export function applyLiveMapDrivers(directory) {
  drivers = directory instanceof Map ? directory : new Map();
  driversError = null;
  renderMarkers();
}

export function reportLiveMapError(err) {
  driversError = err;
  renderMarkers();
}

/* ══ MARKERS ═══════════════════════════════════════════════ */

/** The Google Maps instance created by initAdmMap() in index.html. */
function googleMap() {
  return (typeof admMap !== 'undefined' && admMap) ? admMap : null;
}

function renderMarkers() {
  const map = googleMap();
  if (!map) return;

  const live = new Set();
  const summary = {
    total: 0,
    searching: 0,
    pickup: 0,
    dropoff: 0,
    liveDrivers: 0,
    staleDrivers: 0,
    missingDrivers: 0,
  };
  if (!ridesError) {
    for (const ride of activeRides) {
      const driver = ride.driverId ? drivers.get(ride.driverId) : null;
      const location = driverLocationState(driver);
      summary.total += 1;
      if (ride.status === 'searching') summary.searching += 1;
      if (ride.pickup) summary.pickup += 1;
      if (ride.dropoff) summary.dropoff += 1;
      if (location.current) summary.liveDrivers += 1;
      else if (location.point) summary.staleDrivers += 1;
      else if (ride.status !== 'searching') summary.missingDrivers += 1;

      if (!ride.pickup && !ride.dropoff && !location.point) continue;
      live.add(ride.id);
      upsertRideMarkers(map, ride, driver, location);
    }
  }

  if (ridesError) markers.forEach((_, id) => live.add(id));
  else {
    markers.forEach((entry, rideId) => {
      if (!live.has(rideId)) {
        Object.values(entry.marker).forEach(item => item?.setMap(null));
        entry.infoWindow.close();
        markers.delete(rideId);
      }
    });
  }

  updateStatus(summary);
  if (!hasAutoFitted && summary.total > 0) focusLiveRides();
}

function driverLocationState(driver) {
  if (!driver || driver.status !== 'approved' ||
      !validCoordinates({ lat: driver.lat, lng: driver.lng })) {
    return { point: null, current: false, approximate: false, label: 'No driver GPS' };
  }

  const point = { lat: driver.lat, lng: driver.lng };
  if (driver.approximate) {
    return { point, current: false, approximate: true, label: 'Approximate driver location' };
  }
  if (!driver.updatedAt) {
    return { point, current: false, approximate: false, label: 'Driver GPS time unavailable' };
  }

  const ageMs = Date.now() - driver.updatedAt.getTime();
  const current = driver.isOnline &&
    ageMs >= -LOCATION_FUTURE_TOLERANCE_MS &&
    ageMs <= LOCATION_MAX_AGE_MS;
  return {
    point,
    current,
    approximate: false,
    label: current ? 'Live driver GPS' : `Last driver GPS ${relativeTime(driver.updatedAt)}`,
  };
}

function upsertRideMarkers(map, ride, driver, location) {
  let entry = markers.get(ride.id);
  if (!entry) {
    entry = {
      marker: { driver: null, pickup: null, dropoff: null },
      infoWindow: new google.maps.InfoWindow(),
    };
    markers.set(ride.id, entry);
  }

  entry.infoWindow.setContent(popupHtml(ride, driver, location));
  setMarker(map, entry, 'driver', location.point, {
    title: location.label,
    label: { text: 'T', color: '#fff', fontWeight: '700' },
    fillColor: location.current ? '#C41E3A' : location.approximate ? '#D97706' : '#71717A',
  });
  setMarker(map, entry, 'pickup', ride.pickup, {
    title: 'Passenger pickup point selected in the app',
    label: { text: 'P', color: '#fff', fontWeight: '700' },
    fillColor: '#16A34A',
  });
  setMarker(map, entry, 'dropoff', ride.dropoff, {
    title: 'Ride destination',
    label: { text: 'D', color: '#fff', fontWeight: '700' },
    fillColor: '#2563EB',
  });
}

function setMarker(map, entry, kind, point, options) {
  const existing = entry.marker[kind];
  if (!point) {
    existing?.setMap(null);
    return;
  }

  const markerOptions = {
    map,
    position: point,
    title: options.title,
    label: options.label,
    zIndex: kind === 'driver' ? 30 : kind === 'pickup' ? 20 : 10,
    icon: {
      path: google.maps.SymbolPath.CIRCLE,
      scale: kind === 'driver' ? 10 : 9,
      fillColor: options.fillColor,
      fillOpacity: 1,
      strokeColor: '#fff',
      strokeWeight: 2,
    },
  };

  if (existing) {
    existing.setMap(map);
    existing.setPosition(point);
    existing.setOptions(markerOptions);
    return;
  }

  const marker = new google.maps.Marker(markerOptions);
  marker.addListener('click', () => {
    entry.infoWindow.open({ map, anchor: marker });
  });
  entry.marker[kind] = marker;
}

/* The app shares its selected pickup pin, not a passenger's live GPS. */
function popupHtml(ride, driver, location) {
  const label = RIDE_STATUS_LABELS[ride.status] || ride.status || 'Unknown';
  const driverName = driver?.name ? `<b>${esc(driver.name)}</b><br>` : '';
  const pickup = ride.pickup ? 'Pickup pin shown' : 'Pickup coordinates unavailable';
  const dropoff = ride.dropoff ? 'Destination shown' : 'Destination coordinates unavailable';
  return driverName
       + `${esc(ride.from)} → ${esc(ride.to)}<br>`
       + `${esc(ride.type)} · <b>${esc(label)}</b><br>`
       + `${esc(pickup)} · ${esc(dropoff)}<br>`
       + `<span style="opacity:.75">${esc(location.label)}</span>`;
}

function updateStatus(summary) {
  const box = document.getElementById('map-status');
  if (!box) return;

  box.classList.add('show');
  if (ridesError) {
    box.textContent = 'Ride data unavailable — check admin access or connection';
    return;
  }
  if (driversError) {
    box.textContent = 'Driver updates unavailable — showing last known ride details';
    return;
  }
  if (!ridesLoaded) {
    box.textContent = 'Loading active rides…';
    return;
  }
  if (summary.total === 0) {
    box.textContent = 'No active rides';
    return;
  }

  const rideWord = summary.total === 1 ? 'ride' : 'rides';
  const details = [];
  if (summary.pickup) {
    details.push(`${summary.pickup} pickup${summary.pickup === 1 ? '' : 's'}`);
  }
  if (summary.dropoff) {
    details.push(`${summary.dropoff} destination${summary.dropoff === 1 ? '' : 's'}`);
  }
  if (summary.liveDrivers) {
    details.push(`${summary.liveDrivers} live driver${summary.liveDrivers === 1 ? '' : 's'}`);
  }
  if (summary.staleDrivers) {
    details.push(`${summary.staleDrivers} stale driver GPS`);
  }
  if (summary.missingDrivers) {
    details.push(`${summary.missingDrivers} driver GPS unavailable`);
  }
  if (summary.searching) details.push(`${summary.searching} searching`);
  box.textContent = `${summary.total} active ${rideWord} · ${details.join(' · ')}`;
}

function focusLiveRides() {
  const map = googleMap();
  if (!map) return;
  const mapElement = map.getDiv();
  if (!mapElement.offsetWidth || !mapElement.offsetHeight) return;
  const bounds = new google.maps.LatLngBounds();
  let points = 0;

  activeRides.forEach(ride => {
    [ride.pickup, ride.dropoff].forEach(point => {
      if (!point) return;
      bounds.extend(point);
      points += 1;
    });
    const driver = ride.driverId ? drivers.get(ride.driverId) : null;
    const location = driverLocationState(driver);
    if (location.current && location.point) {
      bounds.extend(location.point);
      points += 1;
    }
  });

  if (!points) return;
  hasAutoFitted = true;
  if (points === 1) {
    map.setCenter(bounds.getCenter());
    map.setZoom(15);
  } else {
    map.fitBounds(bounds, 40);
  }
}

function coordinates(value) {
  const point = value && { lat: value.latitude, lng: value.longitude };
  return validCoordinates(point) ? point : null;
}

function validCoordinates(point) {
  return point &&
    Number.isFinite(point.lat) &&
    Number.isFinite(point.lng) &&
    point.lat >= -90 && point.lat <= 90 &&
    point.lng >= -180 && point.lng <= 180;
}

function text(value, fallback) {
  return (typeof value === 'string' && value.trim()) ? value.trim() : fallback;
}

function esc(s) {
  return String(s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

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

window.renderLiveMap = renderMarkers;
window.focusLiveRides = focusLiveRides;