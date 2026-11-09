// Keep this SDK version aligned with firebase_core_web's supported version.
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDBSEjN0JScFme6KlCFV24SS5BqQHg3g1w',
  appId: '1:990147609261:web:5ffdc39676ed49fcc2fc24',
  messagingSenderId: '990147609261',
  projectId: 'teachersubstitute',
  authDomain: 'teachersubstitute.firebaseapp.com',
  storageBucket: 'teachersubstitute.firebasestorage.app',
  measurementId: 'G-G2ES01T4JW',
});

// FCM displays notification payloads while the app is in the background.
firebase.messaging();
