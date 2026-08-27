/* ══════════════════════════════════════════════════════════
   PolaMove Admin — Firebase data layer
   ──────────────────────────────────────────────────────────
   Replaces the hardcoded DRIVERS / PASSENGERS / RIDES arrays
   with live Firestore data, and makes approve/reject write
   back to the same database the mobile app reads.

   The existing render functions (buildDriversTable, etc.) are
   left untouched — this layer just keeps their input arrays
   in sync and re-renders when Firestore changes.
   ══════════════════════════════════════════════════════════ */

import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js';
import {
  getAuth, signInWithEmailAndPassword, signOut, onAuthStateChanged
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js';
import {
  getFirestore, collection, doc, getDoc, setDoc, onSnapshot,
  updateDoc, serverTimestamp, addDoc, query, orderBy, limit
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js';
import {
  startDashboardStats, stopDashboardStats, applyDriversSnapshot,
  applyUsersSnapshot, applyActiveRidesNow, reportDashboardError
} from './dashboard_stats.js';
import {
  startLiveMap, stopLiveMap, applyLiveMapDrivers, reportLiveMapError
} from './live_map.js';

/* ── CONFIG ────────────────────────────────────────────────
   Copy these values from lib/firebase_options.dart in your
   Flutter project (the `web` block if present, otherwise
   `android` — apiKey, appId, projectId etc. are the same
   project either way).                                      */
const firebaseConfig = {
  apiKey:            "AIzaSyBfzEnKDsuz3GJHOkAozLp9D_MoaVkuy7E",
  authDomain:        "polamove-54ee1.firebaseapp.com",
  projectId:         "polamove-54ee1",
  storageBucket:     "polamove-54ee1.firebasestorage.app",
  messagingSenderId: "688406058644",
  appId:             "1:688406058644:web:5d85ae50e48f5a6c2a8681",
};

const app  = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db   = getFirestore(app);

/* ── STATE ─────────────────────────────────────────────────
   usersById caches users/{uid} so driver and ride rows can
   show real names without a read per row.                   */
const usersById = new Map();
let unsubscribers = [];

/* ══ AUTH ══════════════════════════════════════════════════ */

/**
 * Called by the login form. Signs in, then verifies the account
 * is listed in the `admins` collection before letting them in.
 */
window.adminSignIn = async function (email, password) {
  const cred = await signInWithEmailAndPassword(auth, email.trim(), password);

  const adminDoc = await getDoc(doc(db, 'admins', cred.user.uid));
  if (!adminDoc.exists()) {
    await signOut(auth);
    throw new Error('This account does not have admin access.');
  }

  return adminDoc.data()?.name || email.split('@')[0];
};

window.adminSignOut = function () {
  unsubscribers.forEach(u => u());
  unsubscribers = [];
  stopDashboardStats();
  stopLiveMap();

  // Drop cached rows so the next admin never sees the previous session's data.
  PENDING.length = 0;
  PENDING_STATE = 'loading';
  RIDES.length = 0;
  RIDES_STATE = 'loading';
  DRIVERS.length = 0;
  PASSENGERS.length = 0;

  return signOut(auth);
};

/** Friendly text for Firebase auth error codes. */
window.adminAuthError = function (err) {
  const code = err?.code || '';
  if (code.includes('invalid-credential') ||
      code.includes('wrong-password') ||
      code.includes('user-not-found'))       return 'Incorrect email or password.';
  if (code.includes('invalid-email'))        return 'Enter a valid email address.';
  if (code.includes('too-many-requests'))    return 'Too many attempts. Please wait and try again.';
  if (code.includes('network-request-failed')) return 'No internet connection.';
  return err?.message || 'Sign in failed. Please try again.';
};

/* ══ LIVE DATA ═════════════════════════════════════════════ */

/**
 * Attaches all Firestore listeners. Call once after a
 * successful admin sign-in.
 *
 * Both the login handler and onAuthStateChanged call this on a fresh
 * sign-in, so it guards against attaching every listener twice.
 */
window.startLiveData = function () {
  if (unsubscribers.length) return;

  // users — cached first so driver/ride rows can resolve names
  unsubscribers.push(onSnapshot(collection(db, 'users'), snap => {
    usersById.clear();
    snap.forEach(d => usersById.set(d.id, d.data()));
    refreshPassengers(snap);
    applyUsersSnapshot(snap);
    // Re-render anything that depends on names
    if (window._driverSnap) refreshDrivers(window._driverSnap);
    if (window._rideSnap)   refreshRides(window._rideSnap);
  }, err => {
    console.warn('users listener:', err.message);
    reportDashboardError('passengers', err);
  }));

  unsubscribers.push(onSnapshot(collection(db, 'drivers'), snap => {
    window._driverSnap = snap;
    refreshDrivers(snap);
  }, err => {
    console.warn('drivers listener:', err.message);
    reportDashboardError('drivers', err);
    reportLiveMapError(err);
    PENDING_STATE = 'error';
    if (typeof buildPendingTable === 'function') buildPendingTable();
  }));

  unsubscribers.push(onSnapshot(
    query(collection(db, 'rides'), orderBy('requestedAt', 'desc'), limit(50)),
    snap => {
      window._rideSnap = snap;
      refreshRides(snap);
    },
    // An index error here is normal on first run — Firestore prints a
    // clickable link in the browser console that creates it.
    err => {
      console.warn('rides listener:', err.message);
      reportDashboardError('rides', err);
      RIDES_STATE = 'error';
      if (typeof buildDashRides === 'function') buildDashRides();
    }
  ));

  // Trips / Revenue Today — its own day-scoped listener, because the rides
  // listener above is capped at 50 rows and can't be trusted for a total.
  startDashboardStats(db);

  // Live Ride Monitoring — listens to in-progress rides only; driver positions
  // come from the /drivers snapshot above, so no per-driver listeners.
  startLiveMap(db);
};

/* Resolves users/{uid} out of the cache the users listener keeps warm — one
   collection read for every name on screen, never a read per row.
   `fallback` covers deleted or not-yet-loaded accounts. */
function fullName(uid, fallback = '—') {
  const u = usersById.get(uid);
  if (!u) return fallback;
  return `${u.firstName || ''} ${u.lastName || ''}`.trim() || fallback;
}

/* ── Drivers ───────────────────────────────────────────────
   Maps Firestore shape onto the fields the existing table
   renderer already expects:
     { name, plate, trips, status, uid }
   status: 'pending' | 'online' | 'offline'                  */
function refreshDrivers(snap) {
  // Dashboard reads the raw snapshot — it needs the untouched status/isOnline
  // fields, not the table's collapsed pending/online/offline view.
  applyDriversSnapshot(snap);
  // Live map gets positions from this same snapshot, so tracking a driver
  // costs no reads beyond the registry listener that was already running.
  applyLiveMapDrivers(buildDriverDirectory(snap));

  DRIVERS.length = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.status === 'rejected') return;   // hide rejected applications

    DRIVERS.push({
      uid:    d.id,
      name:   fullName(d.id),
      plate:  v.plateNo || '—',
      trips:  v.totalRides || 0,
      status: v.status === 'pending'
                ? 'pending'
                : (v.isOnline ? 'online' : 'offline'),
    });
  });

  // Sidebar badge + Driver Registry flag, both derived from DRIVERS in
  // index.html so there is exactly one pending count in the console.
  if (typeof renderPendingIndicator === 'function') renderPendingIndicator();

  refreshPendingApplications(snap);

  if (typeof buildDriversTable === 'function') buildDriversTable(DRIVERS);
  // Approved/online counts and the top-driver ranking both come from DRIVERS.
  if (typeof buildReports === 'function') buildReports();
}

/* ── Driver directory (live map) ───────────────────────────
   Flattens drivers/{uid} into what the map needs. `location` is a Firestore
   GeoPoint — its latitude/longitude are read directly, and no lat/lng fields
   are invented. Drivers who are offline have had it cleared to null by
   LocationService.clearLocation(), which lands here as lat/lng = null.       */
function buildDriverDirectory(snap) {
  const directory = new Map();

  snap.forEach(d => {
    const v = d.data();
    const point = v.location;

    directory.set(d.id, {
      name:        fullName(d.id, 'Unknown Driver'),
      status:      v.status || null,
      isOnline:    v.isOnline === true,
      lat:         typeof point?.latitude  === 'number' ? point.latitude  : null,
      lng:         typeof point?.longitude === 'number' ? point.longitude : null,
      approximate: v.locationApproximate === true,
      updatedAt:   v.locationUpdatedAt?.toDate?.() || null,
    });
  });

  return directory;
}

/* ── Pending applications ──────────────────────────────────
   The admin's approval queue. Derived from the same /drivers
   snapshot the registry table uses — no second listener, and
   no /pendingDrivers collection.

   'pending' and 'approved' are the exact values written by
   lib/core/services/auth_service.dart on driver sign-up.     */
function refreshPendingApplications(snap) {
  PENDING.length = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.status !== 'pending') return;

    // Name/contact live in users/{uid} only — never duplicated into drivers.
    const u = usersById.get(d.id) || {};
    const submitted = v.submittedAt?.toDate?.() || null;

    PENDING.push({
      uid:            d.id,
      name:           fullName(d.id),
      status:         v.status,
      submitted,
      submittedLabel: submitted ? formatDate(submitted) : 'Date unknown',
      phone:          u.phone || '—',
      email:          u.email || '—',
      barangay:       u.barangay || '—',
      plate:          v.plateNo || '—',
      licenseNo:      v.licenseNo || '—',
      licenseExpiry:  v.licenseExpiry || '—',
      documents: [
        { label: "Driver's License",   url: webUrl(v.documents?.licenseUrl) },
        { label: 'OR / CR',            url: webUrl(v.documents?.orcrUrl) },
        { label: 'Barangay Clearance', url: webUrl(v.documents?.barangayClearanceUrl) },
      ].map(doc => ({ ...doc, thumbUrl: cloudinaryThumb(doc.url) })),
      storedLocally: v.documentsStoredLocally === true,
    });
  });

  // Newest first. An application with no submittedAt can't be ordered, so it
  // sorts last rather than being dropped out of the queue entirely.
  PENDING.sort((a, b) => {
    if (!a.submitted && !b.submitted) return 0;
    if (!a.submitted) return 1;
    if (!b.submitted) return -1;
    return b.submitted - a.submitted;
  });

  PENDING_STATE = 'ready';
  if (typeof buildPendingTable === 'function') buildPendingTable();
}

/* Only http(s) URLs can be opened from the admin browser. A driver
   registered before the Cloudinary migration (documentsStoredLocally: true)
   has device-local paths instead — a link to one of those would 404, so the
   review modal shows a placeholder instead. */
function webUrl(value) {
  return typeof value === 'string' && /^https?:\/\//i.test(value) ? value : null;
}

/* Cloudinary transformations are just a URL path segment, inserted right
   after /upload/ and before the version/public_id segment — no SDK or
   extra request needed. w_240 caps width at 240px (2x a ~120px thumbnail,
   for retina), and q_auto/f_auto pick quality and format automatically.
   Requesting this instead of the original keeps the review modal well
   inside Cloudinary's free-tier bandwidth. Returns null when there's no
   real URL to transform. */
function cloudinaryThumb(url) {
  return url ? url.replace('/upload/', '/upload/w_240,q_auto,f_auto/') : null;
}

function formatDate(d) {
  return d.toLocaleDateString('en-PH',
    { month: 'short', day: 'numeric', year: 'numeric' });
}

/* ── Passengers ────────────────────────────────────────────
   { name, phone, rides, solo, share, spent }
   Ride counts are filled in by refreshRides().              */
function refreshPassengers(snap) {
  PASSENGERS.length = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.role !== 'passenger') return;
    PASSENGERS.push({
      uid:   d.id,
      name:  `${v.firstName || ''} ${v.lastName || ''}`.trim() || '—',
      phone: v.phone || '—',
      rides: 0, solo: 0, share: 0, spent: 0,
    });
  });

  if (typeof buildPassengersTable === 'function') buildPassengersTable();
  // Registered-passenger count on the Reports panel.
  if (typeof buildReports === 'function') buildReports();
}

/* ── Rides ─────────────────────────────────────────────────
   { id, pass, drv, from, to, type, seats, fare, status, time }
   status: 'active' | 'done' | 'cancelled'                    */
function refreshRides(snap) {
  RIDES.length = 0;

  snap.forEach(d => {
    const v = d.data();

    let status = 'active';
    if (v.status === 'completed') status = 'done';
    else if (v.status === 'cancelled') status = 'cancelled';

    RIDES.push({
      id:     'PM-' + d.id.slice(0, 5).toUpperCase(),
      pass:   fullName(v.passengerId, 'Unknown Passenger'),
      drv:    v.driverId ? fullName(v.driverId) : 'Searching…',
      from:   v.pickup?.name || '—',
      to:     v.dropoff?.name || '—',
      type:   v.rideType || '—',
      seats:  v.seats || 1,
      fare:   v.totalFare || 0,
      status,
      // The Firestore value, kept verbatim, plus a label for display. The
      // `status` above stays a colour bucket so the badge CSS and the Rides
      // page filters keep working unchanged.
      rawStatus:   v.status || 'unknown',
      statusLabel: rideStatusLabel(v.status),
      time:   formatTime(v.requestedAt),
      requestedAtMs: v.requestedAt?.toDate?.()?.getTime() || 0,
      passengerId: v.passengerId,
    });
  });

  RIDES_STATE = 'ready';

  rollUpPassengerStats();

  applyActiveRidesNow(RIDES.filter(r => r.status === 'active').length);

  // Sidebar badge is derived in index.html from the same RIDES array, so
  // there is exactly one active-ride count in the console.
  if (typeof renderRidesIndicator === 'function') renderRidesIndicator();

  if (typeof buildRidesTable === 'function') buildRidesTable();
  if (typeof buildPassengersTable === 'function') buildPassengersTable();
  // Dashboard "Recent Rides" — without this the card only refreshed when you
  // navigated back to the dashboard, so a new booking never appeared live.
  if (typeof buildDashRides === 'function') buildDashRides();
  // Reports are derived from RIDES, so they go stale without this.
  if (typeof buildReports === 'function') buildReports();
}

/** Derives per-passenger totals from the loaded rides. */
function rollUpPassengerStats() {
  PASSENGERS.forEach(p => { p.rides = 0; p.solo = 0; p.share = 0; p.spent = 0; });

  RIDES.forEach(r => {
    if (r.status !== 'done') return;
    const p = PASSENGERS.find(x => x.uid === r.passengerId);
    if (!p) return;
    p.rides += 1;
    p.spent += r.fare;
    if (r.type === 'PolaSolo')  p.solo  += 1;
    if (r.type === 'PolaShare') p.share += 1;
  });
}

/* Display labels only. Keys are the exact statuses written by
   lib/core/services/ride_service.dart — the stored value is never rewritten. */
const RIDE_STATUS_LABELS = {
  searching: 'Searching',
  accepted:  'Accepted',
  arrived:   'Arrived',
  ongoing:   'Ongoing',
  completed: 'Done',
  cancelled: 'Cancelled',
};

function rideStatusLabel(status) {
  return RIDE_STATUS_LABELS[status] || status || 'Unknown';
}

function formatTime(ts) {
  if (!ts?.toDate) return '—';
  return ts.toDate().toLocaleTimeString('en-PH',
    { hour: 'numeric', minute: '2-digit', hour12: true });
}

/* ══ DRIVER APPROVAL ═══════════════════════════════════════ */

/**
 * Sets drivers/{uid}.status. The mobile app streams this field,
 * so the driver's phone updates the moment it's written — no
 * app restart, no notification plumbing required.
 *
 * documentsOutdated / documentChangeNote are cleared on both
 * approve and reject: either way the admin has now looked at the
 * application, so the "documents may not match" warning has served
 * its purpose and must not persist onto the next review.
 */
async function setDriverStatus(uid, status) {
  await updateDoc(doc(db, 'drivers', uid), {
    status,
    documentsOutdated: false,
    documentChangeNote: '',
    reviewedAt: serverTimestamp(),
    reviewedBy: auth.currentUser?.uid || null,
  });

  // Best-effort in-app notification. Failure here must not break approval.
  try {
    await addDoc(collection(db, 'notifications'), {
      userId:   uid,
      title:    status === 'approved' ? 'Application approved' : 'Application not approved',
      message:  status === 'approved'
        ? 'Your driver application has been approved. You can now go online and accept rides.'
        : 'Your driver application was not approved. Please contact the administrator.',
      category: 'account',
      read:     false,
      createdAt: serverTimestamp(),
    });
  } catch (e) {
    console.warn('notification write failed:', e.message);
  }
}

window.approveDriverByUid = async function (uid, name) {
  try {
    await setDriverStatus(uid, 'approved');
    showToast('✅ ' + name + ' approved! They can now go online.', 'grn');
  } catch (e) {
    showToast('Could not approve: ' + e.message, 'red');
  }
};

window.rejectDriverByUid = async function (uid, name) {
  try {
    await setDriverStatus(uid, 'rejected');
    showToast('❌ ' + name + ' registration rejected.', 'red');
  } catch (e) {
    showToast('Could not reject: ' + e.message, 'red');
  }
};

/* Keeps the existing name-based calls in the HTML working. */
window.approveDriverInline = function (name) {
  const d = DRIVERS.find(x => x.name === name);
  if (d) window.approveDriverByUid(d.uid, name);
};

window.rejectDriverInline = function (name) {
  const d = DRIVERS.find(x => x.name === name);
  if (d) window.rejectDriverByUid(d.uid, name);
};

/* ══ FARE SETTINGS ═════════════════════════════════════════
   One settings/fares document holding all three ride types plus a `routes`
   map of per-route overrides. Read on demand rather than via a listener —
   fares change rarely, and a standing listener would cost a read on every
   admin page load for data nobody is watching.

   The mobile app reads this document once per launch via FareService (see
   lib/core/services/fare_service.dart) — a save here reaches a passenger the
   next time they open the app, not their current session. The panel says so
   on screen. */

/** Returns the stored fare map, or null when nothing has been saved yet. */
window.loadFareSettings = async function () {
  const snap = await getDoc(doc(db, 'settings', 'fares'));
  return snap.exists() ? snap.data() : null;
};

/** merge:true so a future key added to this document isn't wiped by an
    older console that doesn't know about it. */
window.saveFareSettings = async function (values) {
  await setDoc(doc(db, 'settings', 'fares'), {
    ...values,
    updatedAt: serverTimestamp(),
    updatedBy: auth.currentUser?.uid || null,
  }, { merge: true });
};

/** Merges only the given {fareKey: number} route overrides into
    settings/fares.routes, via dotted field paths — so this never clobbers a
    route another admin session already customised, and never touches routes
    this session didn't render. updateDoc (unlike setDoc) requires the
    document to already exist; in practice it does, since going online with
    the app itself never happens before an admin has set up fares, but a
    truly first-ever save should use "Save Fares" (Ride Type Fares) first.

    Named saveRouteFareOverrides, not saveRouteFares — index.html's own
    saveRouteFares() (the "Save Routes" button's handler) is a plain
    top-level function in a classic (non-module) script, which makes it a
    window property too. A same-named window.saveRouteFares assigned here
    would silently overwrite it once this deferred module runs, so the
    button's own handler would end up calling itself with no arguments. */
window.saveRouteFareOverrides = async function (routeFares) {
  const updates = {};
  for (const [key, value] of Object.entries(routeFares)) {
    updates[`routes.${key}`] = value;
  }
  updates.updatedAt = serverTimestamp();
  updates.updatedBy = auth.currentUser?.uid || null;
  await updateDoc(doc(db, 'settings', 'fares'), updates);
};

/* ══ ADMIN IDENTITY ════════════════════════════════════════ */

/** Name from admins/{uid} plus the signed-in email, for the sidebar popover. */
window.getAdminIdentity = async function () {
  const user = auth.currentUser;
  if (!user) return null;

  let name = null;
  try {
    const adminDoc = await getDoc(doc(db, 'admins', user.uid));
    name = adminDoc.data()?.name || null;
  } catch (_) { /* fall back to the email's local part below */ }

  return {
    name:  name || user.email?.split('@')[0] || 'Admin',
    email: user.email || '—',
  };
};

/* ══ SESSION RESTORE ═══════════════════════════════════════ */
onAuthStateChanged(auth, async user => {
  if (!user) return;
  const adminDoc = await getDoc(doc(db, 'admins', user.uid));
  if (!adminDoc.exists()) { await signOut(auth); return; }

  // Skip the login screen on refresh
  const ls = document.getElementById('login-screen');
  const al = document.getElementById('admin-layout');
  if (ls && al && al.style.display !== 'flex') {
    ls.classList.add('hidden');
    ls.style.display = 'none';
    al.style.display = 'flex';
  }
  window.startLiveData();
});