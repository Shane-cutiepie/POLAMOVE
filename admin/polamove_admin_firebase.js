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
  getFirestore, collection, doc, getDoc, onSnapshot,
  updateDoc, serverTimestamp, addDoc, query, orderBy, limit
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js';

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
 */
window.startLiveData = function () {
  // users — cached first so driver/ride rows can resolve names
  unsubscribers.push(onSnapshot(collection(db, 'users'), snap => {
    usersById.clear();
    snap.forEach(d => usersById.set(d.id, d.data()));
    refreshPassengers(snap);
    // Re-render anything that depends on names
    if (window._driverSnap) refreshDrivers(window._driverSnap);
    if (window._rideSnap)   refreshRides(window._rideSnap);
  }));

  unsubscribers.push(onSnapshot(collection(db, 'drivers'), snap => {
    window._driverSnap = snap;
    refreshDrivers(snap);
  }));

  unsubscribers.push(onSnapshot(
    query(collection(db, 'rides'), orderBy('requestedAt', 'desc'), limit(50)),
    snap => {
      window._rideSnap = snap;
      refreshRides(snap);
    },
    // An index error here is normal on first run — Firestore prints a
    // clickable link in the browser console that creates it.
    err => console.warn('rides listener:', err.message)
  ));
};

function fullName(uid) {
  const u = usersById.get(uid);
  if (!u) return '—';
  return `${u.firstName || ''} ${u.lastName || ''}`.trim() || '—';
}

/* ── Drivers ───────────────────────────────────────────────
   Maps Firestore shape onto the fields the existing table
   renderer already expects:
     { name, plate, route, trips, rating, status, uid }
   status: 'pending' | 'online' | 'offline'                  */
function refreshDrivers(snap) {
  DRIVERS.length = 0;

  snap.forEach(d => {
    const v = d.data();
    if (v.status === 'rejected') return;   // hide rejected applications

    DRIVERS.push({
      uid:    d.id,
      name:   fullName(d.id),
      plate:  v.plateNo || '—',
      route:  v.preferredRoute || '—',
      trips:  v.totalRides || 0,
      rating: v.rating || 0,
      status: v.status === 'pending'
                ? 'pending'
                : (v.isOnline ? 'online' : 'offline'),
    });
  });

  const pending = DRIVERS.filter(x => x.status === 'pending').length;
  const badge = document.getElementById('pending-badge');
  if (badge) {
    badge.textContent = pending;
    badge.style.display = pending > 0 ? '' : 'none';
  }

  if (typeof buildDriversTable === 'function') buildDriversTable(DRIVERS);
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
      pass:   fullName(v.passengerId),
      drv:    v.driverId ? fullName(v.driverId) : 'Searching…',
      from:   v.pickup?.name || '—',
      to:     v.dropoff?.name || '—',
      type:   v.rideType || '—',
      seats:  v.seats || 1,
      fare:   v.totalFare || 0,
      status,
      time:   formatTime(v.requestedAt),
      passengerId: v.passengerId,
    });
  });

  rollUpPassengerStats();

  const activeCount = RIDES.filter(r => r.status === 'active').length;
  const badge = document.getElementById('rides-badge');
  if (badge) {
    badge.textContent = activeCount;
    badge.style.display = activeCount > 0 ? '' : 'none';
  }

  if (typeof buildRidesTable === 'function') buildRidesTable();
  if (typeof buildPassengersTable === 'function') buildPassengersTable();
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
 */
async function setDriverStatus(uid, status) {
  await updateDoc(doc(db, 'drivers', uid), {
    status,
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