
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }

    throw UnsupportedError(
      'यो platform अहिले समर्थित छैन।',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDYzIfJEkVRgt72zzgTOa0eDYIGxLfWla4',
    appId: '1:616890611099:android:a8e82caffe865d680b9d3e',
    messagingSenderId: '616890611099',
    projectId: 'paribarik-bachat-kosh',
    storageBucket: 'paribarik-bachat-kosh.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD5zdCUUtEurnLBXk7M3XOu7xEnGtK2CX0',
    appId: '1:616890611099:web:e63a51538a284b550b9d3e',
    messagingSenderId: '616890611099',
    projectId: 'paribarik-bachat-kosh',
    authDomain: 'paribarik-bachat-kosh.firebaseapp.com',
    storageBucket: 'paribarik-bachat-kosh.firebasestorage.app',
  );
}
