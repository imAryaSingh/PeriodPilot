import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/network/connectivity_status.dart';
import 'features/auth/data/local_auth_store.dart';
import 'features/auth/data/firebase_auth_store.dart';
import 'features/auth/presentation/local_auth_controller.dart';
import 'features/school/data/local_school_database.dart';
import 'features/school/data/firebase_school_database.dart';
import 'features/school/data/school_database.dart';
import 'features/notifications/data/firebase_notification_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final useFirebase = kIsWeb || defaultTargetPlatform == TargetPlatform.android;
  if (useFirebase) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      webPersistentTabManager: kIsWeb
          ? WebPersistentMultipleTabManager()
          : null,
    );
  }
  final authController = LocalAuthController(
    LocalAuthStore(),
    firebaseStore: useFirebase ? FirebaseAuthStore() : null,
    notificationService: useFirebase ? FirebaseNotificationService() : null,
  );
  await authController.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityStatus()),
        ChangeNotifierProvider.value(value: authController),
        Provider<SchoolDatabase>(
          create: (_) =>
              useFirebase ? FirebaseSchoolDatabase() : LocalSchoolDatabase(),
        ),
        if (useFirebase)
          Provider<FirebaseNotificationService>.value(
            value: authController.notificationService!,
          ),
        if (useFirebase)
          Provider<FirebaseNotificationRepository>(
            create: (_) => FirebaseNotificationRepository(),
          ),
      ],
      child: const TeacherSubstituteApp(),
    ),
  );
}
