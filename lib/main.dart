import 'package:flutter/material.dart';
import 'bank_payment_details_page.dart';
import 'insurance_management_page.dart';
import 'admin_insurance_management_page.dart';
import 'app_update_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'monthly_savings_service.dart';
import 'payment_service.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'loan_service.dart';
import 'late_payment_service.dart';
import 'penalty_service.dart';
import 'penalty_management_page.dart';
import 'fund_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'late_payment_notice_page.dart';
import 'admin_late_payment_notice_page.dart';
import 'notification_page.dart';
import 'notification_service.dart';
import 'dashboard_anniversary_banner.dart';
import 'admin_anniversary_management_page.dart';
import 'admin_member_management_page.dart';
import 'nepali_digits.dart';
import 'financial_report_page.dart';
import 'expense_withdrawal_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel notificationChannel =
    AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'पारिवारिक बचत कोषका सूचनाहरू',
  importance: Importance.max,
);

Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(notificationChannel);
await androidPlugin?.requestNotificationsPermission();
}
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
    await _initializeLocalNotifications();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
 FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  final notification = message.notification;

  if (notification != null) {
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title ?? 'पारिवारिक बचत कोष',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannel.id,
          notificationChannel.name,
          channelDescription: notificationChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
});

  await Supabase.initialize(
  url: 'https://ymxxsqblkskuehhylwbd.supabase.co',
  anonKey: 'sb_publishable_UUmW6vNH-t__YheswtyQNQ_w-s1SYhG',
  accessToken: () async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return null;
    }

    return await user.getIdToken();
  },
);

  runApp(const ParibarikBachatKoshApp());
}

const Color navy = Color(0xFF08254A);
const Color deepNavy = Color(0xFF06172F);
const Color gold = Color(0xFFE8B943);
const Color goldLight = Color(0xFFFFE7A0);

class ParibarikBachatKoshApp extends StatelessWidget {
  const ParibarikBachatKoshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'पारिवारिक बचत कोष',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: deepNavy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoggingIn = false;
    
@override
void initState() {
  super.initState();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkForAppUpdate();
  });
}

Future<void> _checkForAppUpdate() async {
  final update = await AppUpdateService.checkForUpdate();

  if (!mounted || update == null) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: !update.forceUpdate,
    builder: (dialogContext) {
      return PopScope(
        canPop: !update.forceUpdate,
        child: AlertDialog(
          title: const Text('नयाँ अपडेट उपलब्ध छ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('नयाँ Version: ${update.latestVersion}'),
              const SizedBox(height: 10),
              if (update.releaseNotes.isNotEmpty)
                Text(update.releaseNotes),
              const SizedBox(height: 10),
              const Text(
                'एपको नयाँ संस्करण डाउनलोड गरेर अपडेट गर्नुहोस्।',
              ),
            ],
          ),
          actions: [
            if (!update.forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('पछि गर्नुहोस्'),
              ),
            ElevatedButton(
              onPressed: () async {
                final openedInstaller =
                    await AppUpdateService.downloadAndInstall(update.apkUrl);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (!openedInstaller && mounted) {
                  _showMessage(
                    'अपडेट डाउनलोड वा Installer खोल्न सकिएन। इन्टरनेट जाँचेर फेरि प्रयास गर्नुहोस्।',
                  );
                }
              },
              child: const Text('Update गर्नुहोस्'),
            ),
          ],
        ),
      );
    },
  );
}

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
  final bool isSuccess = message.contains('सफल');

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: isSuccess ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

  Future<void> _registerFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  debugPrint('FCM CHECK: register function called');
  debugPrint('FCM USER: ${user?.uid}');
  if (user == null) return;

  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
      debugPrint('FCM STEP: permission completed');
debugPrint('FCM PERMISSION: ${settings.authorizationStatus}');

  if (settings.authorizationStatus ==
      AuthorizationStatus.denied) {
    return;
  }
debugPrint('FCM STEP: requesting token');
  final token = await messaging.getToken(
  vapidKey: 'BCm0bm5tRGtNeyK_ir4wsQcUJ9E5FJFJpYaa62Bb53kcqwApmFHDqB5GkUaK8IYz8AgUYqQqAIkP6S4_X7RLmeM',
);
      debugPrint('FCM TOKEN: $token');
  if (token == null) return;
      
      await FirebaseFirestore.instance
    .collection('member')
    .doc(user.uid)
    .set({
  'fcmTestToken': token,
}, SetOptions(merge: true));

  final memberRef = FirebaseFirestore.instance
      .collection('member')
      .doc(user.uid);

  await memberRef.set({
    'fcmTokens': FieldValue.arrayUnion([token]),
    'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  messaging.onTokenRefresh.listen((newToken) async {
    await memberRef.set({
      'fcmTokens': FieldValue.arrayUnion([newToken]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}
    
Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

if (_isLoggingIn) return;

setState(() {
  _isLoggingIn = true;
});
  final email = _usernameController.text.trim();
  final password = _passwordController.text;

  try {
    final credential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      _showMessage('Login सफल भएन। फेरि प्रयास गर्नुहोस्।');
      return;
    }

    final memberDoc = await FirebaseFirestore.instance
        .collection('member')
        .doc(user.uid)
        .get();

    if (!memberDoc.exists) {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _showMessage('सदस्य विवरण भेटिएन। Firebase मा UID जाँच्नुहोस्।');
      return;
    }

    if (!mounted) return;

    final data = memberDoc.data()!;
    final role = data['role']?.toString() ?? 'member';
          try {
      await _registerFcmToken();
    } catch (e) {
      debugPrint('FCM Token registration failed: $e');
    }

  _showMessage('Login सफल भयो। भूमिका: $role');

await Future.delayed(const Duration(milliseconds: 500));

if (!mounted) return;

Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => DashboardPage(
      memberName: data['name']?.toString() ?? '',
      role: role,
      uid: user.uid,
    ),
  ),
);


  } on FirebaseAuthException catch (e) {

  switch (e.code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      _showMessage('Email वा Password मिलेन।');
      break;

    case 'invalid-email':
      _showMessage('सही Email लेख्नुहोस्।');
      break;

    case 'user-disabled':
      _showMessage('यो खाता निष्क्रिय छ।');
      break;

    case 'too-many-requests':
      _showMessage('धेरै प्रयास भयो। केही समयपछि फेरि प्रयास गर्नुहोस्।');
      break;

    default:
      _showMessage('Login समस्या: ${e.message ?? e.code}');
  }
} catch (e) {
  if (!mounted) return;
  _showMessage('त्रुटि भयो: $e');
} finally {
  if (mounted) {
    setState(() {
      _isLoggingIn = false;
    });
  }
}
}

Future<void> _forgotPassword() async {
  final emailController = TextEditingController();

  final email = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('पासवर्ड बिर्सनुभयो?'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'दर्ता भएको Email लेख्नुहोस्',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('रद्द गर्नुहोस्'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                emailController.text.trim(),
              );
            },
            child: const Text('Reset Link पठाउनुहोस्'),
          ),
        ],
      );
    },
  );

  emailController.dispose();

  if (email == null || email.isEmpty) return;

  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(
      email: email,
    );

    if (!mounted) return;

    _showMessage(
  'Password Reset Link सफलतापूर्वक पठाइएको छ।',
);
  } on FirebaseAuthException catch (e) {
    if (!mounted) return;

    if (e.code == 'invalid-email') {
      _showMessage('कृपया सही Email लेख्नुहोस्।');
    } else if (e.code == 'too-many-requests') {
      _showMessage('धेरै प्रयास भयो। केही समयपछि पुनः प्रयास गर्नुहोस्।');
    } else {
      _showMessage('Reset Link पठाउन समस्या भयो।');
    }
  } catch (e) {
    if (!mounted) return;
    _showMessage('Reset Link पठाउन समस्या भयो।');
  }
}
    
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // सम्पूर्ण स्क्रिनको गाढा नीलो background
          const ColoredBox(color: deepNavy),

          // परिवारको फोटो: स्क्रिनको माथिल्लो ५०% मात्र
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.5,
            child: Image.asset(
              'assets/family_background.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) {
                return const ColoredBox(color: navy);
              },
            ),
          ),

          // फोटोको तल्लो किनारामा मात्र gradient transition
          // फोटोको बीचमा कुनै blur छैन
          Positioned(
            top: screenHeight * 0.38,
            left: 0,
            right: 0,
            height: screenHeight * 0.12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      deepNavy.withValues(alpha: 0.0),
                      deepNavy.withValues(alpha: 0.30),
                      deepNavy.withValues(alpha: 0.75),
                      deepNavy,
                    ],
                    stops: const [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // फोटो सकिएपछि तल्लो ५०% गाढा नीलो
          Positioned(
            top: screenHeight * 0.5,
            left: 0,
            right: 0,
            bottom: 0,
            child: const ColoredBox(color: deepNavy),
          ),

          // Login screen content: पहिलेकै डिजाइन
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(25, 0, 25, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              SizedBox(height: screenHeight * 0.245),

                              // आधिकारिक लोगो
                              Container(
                                width: 116,
                                height: 116,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      goldLight,
                                      gold,
                                      Color(0xFF9D762D),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: gold.withValues(alpha: 0.30),
                                      blurRadius: 20,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/official_logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const ColoredBox(
                                        color: navy,
                                        child: Icon(
                                          Icons.account_balance,
                                          color: gold,
                                          size: 55,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              const Text(
                                'पारिवारिक बचत कोष',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: goldLight,
                                  fontSize: 29,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 5),

                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      endIndent: 12,
                                      thickness: 0.7,
                                    ),
                                  ),
                                  Text(
                                    'सधैं बचत, सुरक्षित भविष्य',
                                    style: TextStyle(
                                      color: goldLight,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      indent: 12,
                                      thickness: 0.7,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 28),

                              // Username / Email / Mobile
                              _GoldTextField(
                                controller: _usernameController,
                                hint: 'Username / Email / Mobile',
                                icon: Icons.person_outline,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'कृपया Username वा Email लेख्नुहोस्।';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              // Password
                              _GoldTextField(
                                controller: _passwordController,
                                hint: 'Password',
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'कृपया Password लेख्नुहोस्।';
                                  }
                                  return null;
                                },
                                suffix: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: gold,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Remember me / Forgot password
                              Row(
                                children: [
                                  SizedBox(
                                    width: 30,
                                    height: 35,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: gold,
                                      checkColor: navy,
                                      side: const BorderSide(color: gold),
                                      onChanged: (value) {
                                        setState(() {
                                          _rememberMe = value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  const Expanded(
                                    child: Text(
                                      'Remember me',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
 TextButton(
 onPressed: _forgotPassword,
    child: const Text(
    'Forgot Password?',
     style: TextStyle(
    color: goldLight,
    fontSize: 12,
                  ),
                 ),
                ),
               ],
              ),

                              const SizedBox(height: 12),

                              // Login button
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFD9A52E),
                                        goldLight,
                                        Color(0xFFD9A52E),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: ElevatedButton(
   onPressed: _isLoggingIn ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: navy,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
 child: _isLoggingIn
    ? const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: navy,
        ),
      )
    : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Login',
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: 18),
                                        Icon(Icons.arrow_forward, size: 27),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 22),

                              // OR divider
                              const Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      thickness: 0.6,
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: goldLight,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      thickness: 0.6,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Google login
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showMessage(
                                      'Google Login Firebase मा जडान '
                                      'गरेपछि सक्रिय हुनेछ।',
                                    );
                                  },
                                  icon: const Text(
                                    'G',
                                    style: TextStyle(
                                      color: Color(0xFF4285F4),
                                      fontSize: 27,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  label: const Text(
                                    'Continue with Google',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: gold,
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 22),

                              // Register
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  const Text(
                                    'खाता छैन ? ',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _showMessage(
                                        'Register सुविधा Firebase सँग '
                                        'जडान गरिनेछ।',
                                      );
                                    },
                                    child: const Text(
                                      'दर्ता गर्नुहोस् →',
                                      style: TextStyle(
                                        color: goldLight,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 28),

                              // Decorative mountain divider
                              const Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      thickness: 0.6,
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: Icon(
                                      Icons.landscape_outlined,
                                      color: gold,
                                      size: 34,
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: gold,
                                      thickness: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// GOLD OUTLINED INPUT FIELD

class _GoldTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const _GoldTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.validator,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: gold,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.white60,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: gold, size: 23),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF08254A).withValues(alpha: 0.88),
  
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 19,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: gold, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.red, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}

// DASHBOARD PAGE

class DashboardPage extends StatefulWidget {
  final String memberName;
  final String role;
  final String uid;

  const DashboardPage({
    super.key,
    required this.memberName,
    required this.role,
    required this.uid,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
    
final MonthlySavingsService _savingsService =
    MonthlySavingsService();
  int selectedIndex = 0;
bool isAdminMode = false;
bool _accountDeactivated = false;
bool _accountStatusLoaded = false;
bool _biometricPrompted = false;
Timer? _deactivationTimer;
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _accountStatusSubscription;

Future<void> _refreshAccountStatus() async {
  if (widget.role.toLowerCase() == 'admin') {
    if (mounted) setState(() { _accountDeactivated = false; _accountStatusLoaded = true; });
    return;
  }
  try {
    final ref = FirebaseFirestore.instance.collection('member').doc(widget.uid);
    final snapshot = await ref.get();
    final data = snapshot.data() ?? {};
    final until = data['deactivationEndsAt'];
    final startsValue = data['deactivationStartsAt'];
    final startsAt = startsValue is Timestamp ? startsValue.toDate() : null;
    var inactive = data['accountActive'] == false;
    _deactivationTimer?.cancel();
    if (!inactive && data['deactivationMode'] == 'fixed' && startsAt != null && startsAt.isAfter(DateTime.now())) {
      _deactivationTimer = Timer(startsAt.difference(DateTime.now()), () async {
        await ref.set({
          'accountActive': false,
          'deactivatedAt': FieldValue.serverTimestamp(),
          'accountStatusUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _accountDeactivated = true);
      });
    }
    if (!inactive && data['deactivationMode'] == 'fixed' && startsAt != null &&
        !startsAt.isAfter(DateTime.now()) && until is Timestamp && until.toDate().isAfter(DateTime.now())) {
      await ref.set({
        'accountActive': false,
        'deactivatedAt': Timestamp.fromDate(startsAt),
        'accountStatusUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      inactive = true;
    }
    if (inactive && data['deactivationMode'] == 'fixed' && until is Timestamp && until.toDate().isAfter(DateTime.now())) {
      final delay = until.toDate().difference(DateTime.now());
      _deactivationTimer = Timer(delay, () async {
        await ref.set({
          'accountActive': true,
          'deactivationStartsAt': null,
          'deactivationEndsAt': null,
          'reactivatedAt': FieldValue.serverTimestamp(),
          'penaltyResumeAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 10))),
          'penaltyResumeMode': 'fixed_period',
          'deactivationAutoReactivatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _accountDeactivated = false);
      });
    }
    if (inactive && data['deactivationMode'] == 'fixed' && until is Timestamp && !until.toDate().isAfter(DateTime.now())) {
      await ref.set({
        'accountActive': true,
        'deactivationStartsAt': null,
        'deactivationEndsAt': null,
        'reactivatedAt': Timestamp.fromDate(until.toDate()),
        'penaltyResumeAt': Timestamp.fromDate(until.toDate().add(const Duration(days: 10))),
        'penaltyResumeMode': 'fixed_period',
        'deactivationAutoReactivatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      inactive = false;
    }
    if (mounted) setState(() { _accountDeactivated = inactive; _accountStatusLoaded = true; });
  } catch (e) {
    debugPrint('Account status check failed: $e');
    if (mounted) setState(() => _accountStatusLoaded = true);
  }
}

Future<void> _verifyBiometricOnOpen() async {
  if (_biometricPrompted || widget.role.toLowerCase() == 'admin') return;
  _biometricPrompted = true;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('biometric_enabled_${widget.uid}') != true) return;
  try {
    final auth = LocalAuthentication();
    final supported = await auth.isDeviceSupported();
    final enrolled = await auth.getAvailableBiometrics();
    if (!supported || enrolled.isEmpty) throw Exception('यस मोबाइलमा Biometric उपलब्ध छैन।');
    final ok = await auth.authenticate(
      localizedReason: 'पारिवारिक बचत कोषमा प्रवेश गर्न पहिचान पुष्टि गर्नुहोस्।',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
    if (!ok) await FirebaseAuth.instance.signOut();
  } catch (e) {
    debugPrint('Biometric verification failed: $e');
    await FirebaseAuth.instance.signOut();
  }
}
  Stream<QuerySnapshot<Map<String, dynamic>>> get _allSavingsRecords {
    return _savingsService.watchAllRecords();
  }
    final List<String> titles = [
    'ड्यासबोर्ड',
    'मासिक बचत',
    'ऋण व्यवस्थापन',
    'मेरो खाता',
  ];
    
@override
void initState() {
  super.initState();
  _refreshAccountStatus();
  if (widget.role.toLowerCase() != 'admin') {
    _accountStatusSubscription = FirebaseFirestore.instance
        .collection('member').doc(widget.uid).snapshots().listen((_) {
      _refreshAccountStatus();
    });
  }
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _verifyBiometricOnOpen();
    try {
      await LatePaymentService().processExpiredNotices(
        memberUid: widget.uid,
      );
    } catch (e) {
      debugPrint('Late payment जाँच गर्दा त्रुटि: $e');
    }
  });
}
 @override
 void dispose() {
   _deactivationTimer?.cancel();
   _accountStatusSubscription?.cancel();
   super.dispose();
 }

 @override
   Widget build(BuildContext context) {
    final bool isAdmin =      widget.role.toLowerCase() == 'admin';
    final bool isMemberMode =  selectedIndex == 4;

  return Scaffold(
   appBar: AppBar(
  toolbarHeight: 84,
  backgroundColor: const Color(0xFFFFB02E),
  foregroundColor: const Color(0xFF102A43),
  elevation: 3,
  titleSpacing: 8,
  title: Row(
    children: [
      Image.asset(
        'assets/official_logo.png',
        height: 62,
        width: 62,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(
          Icons.savings,
          size: 50,
          color: Color(0xFF102A43),
        ),
      ),
      const SizedBox(width: 8),
      const Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'पारिवारिक बचत कोष',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF102A43),
                ),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'स्थापना–२०८३, कार्तिक',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF102A43),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
  actions: [
  if (!isAdminMode && !_accountDeactivated)
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('memberUid', isEqualTo: widget.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = (snapshot.data?.docs ?? [])
            .where((doc) => doc.data()['isRead'] != true)
            .length;

        return Stack(
          children: [
            IconButton(
              tooltip: 'सूचनाहरू',
              icon: const Icon(Icons.notifications, size: 25),
              onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NotificationPage(memberUid: widget.uid),
    ),
  );
},
            ),
            if (unreadCount > 0)
              Positioned(
                right: 5,
                top: 5,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: Colors.red,
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  IconButton(
    tooltip: 'Logout',
    icon: const Icon(Icons.logout, size: 24),
    onPressed: () async {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
    },
  ),
],
),
body: isAdminMode
      ? const AdminDashboardPage()
    : (!_accountStatusLoaded
        ? const Center(child: CircularProgressIndicator())
        : (_accountDeactivated
            ? _DeactivatedMemberDashboard(uid: widget.uid, memberName: widget.memberName)
            : selectedIndex == 0
        ? DashboardContent(
            memberName: widget.memberName,
            uid: widget.uid,
          )
        : selectedIndex == 1
            ? LoanMenuPage(
                memberName: widget.memberName,
                uid: widget.uid,
              )
          : selectedIndex == 2
    ? VotingMenuPage(
        memberName: widget.memberName,
        uid: widget.uid,
      )
   : MemberProfilePage(uid: widget.uid))),


bottomNavigationBar: (!isAdmin && _accountDeactivated)
    ? null
    : isAdmin
    ? SafeArea(
        child: SizedBox(
          height: 82,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!isAdminMode)
  NavigationBar(
                selectedIndex: isAdminMode ? 0 : selectedIndex,
                onDestinationSelected: (index) {
  setState(() {
    selectedIndex = index;
  });
},
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'ड्यासबोर्ड',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_outlined),
                    selectedIcon: Icon(Icons.account_balance),
                    label: 'ऋण',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.how_to_vote_outlined),
                    selectedIcon: Icon(Icons.how_to_vote),
                    label: 'मतदान',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'मेरो खाता',
                  ),
                ],
              ),
              Positioned(
                top: -17,
                child: Material(
                  color: const Color(0xFFE8C56A),
                  elevation: 8,
                  shape: const CircleBorder(
                    side: BorderSide(
                      color: Color(0xFFFFE7A0),
                      width: 3,
                    ),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() {
                        isAdminMode = !isAdminMode;
                        selectedIndex = 0;
                      });
                    },
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Icon(
                        isAdminMode
                            ? Icons.person
                            : Icons.admin_panel_settings,
                        size: 32,
                        color: const Color(0xFF101B3A),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      )
    : NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'ड्यासबोर्ड',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'ऋण',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_vote_outlined),
            selectedIcon: Icon(Icons.how_to_vote),
            label: 'मतदान',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'मेरो खाता',
          ),
        ],
      ),

  );
  }
}

class _DeactivatedMemberDashboard extends StatelessWidget {
  final String uid;
  final String memberName;
  const _DeactivatedMemberDashboard({required this.uid, required this.memberName});

  @override
  Widget build(BuildContext context) {
    final normalized = memberName.trim().replaceAll(RegExp(r'\s+'), '');
    final index = DashboardContent.names.indexWhere((name) => name.replaceAll(RegExp(r'\s+'), '') == normalized);
    final safe = index < 0 ? 0 : index;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _DashboardAtmCard(
        name: memberName.isEmpty ? DashboardContent.names[safe] : memberName,
        photo: DashboardContent.photos[safe],
        background: DashboardContent.backgrounds[safe],
        savings: 'XXX', loan: 'XXX', large: true, redacted: true,
      ),
      const SizedBox(height: 12),
      const Card(child: Padding(
        padding: EdgeInsets.all(18),
        child: Text('तपाईंको खाता निष्क्रिय छ। कृपया Admin लाई सम्पर्क गर्नुहोस्।',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17)),
      )),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF102A43), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange)),
        child: const Column(children: [
          Text('संस्थाको कुल बचत', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: 5),
          Text('XXX', style: TextStyle(color: Colors.red, fontSize: 23, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 12),
      const Row(children: [
        Expanded(child: SummaryCard(title: 'कुल बचत', amount: 'XXX', icon: Icons.savings, color: Colors.red)),
        SizedBox(width: 8),
        Expanded(child: SummaryCard(title: 'बिमा', amount: 'XXX', icon: Icons.health_and_safety_outlined, color: Colors.red)),
      ]),
      const SizedBox(height: 10),
      const Row(children: [
        Expanded(child: SummaryCard(title: 'ऋण', amount: 'XXX', icon: Icons.account_balance, color: Colors.red)),
        SizedBox(width: 8),
        Expanded(child: SummaryCard(title: 'उपलब्ध कोष', amount: 'XXX', icon: Icons.account_balance_wallet, color: Colors.red)),
      ]),
    ]);
  }
}

class VotingMenuPage extends StatelessWidget {
  final String memberName;
  final String uid;

  const VotingMenuPage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मतदान'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance),
              ),
              title: const Text(
                'ऋण मतदान',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'ऋण आवेदनमा Agree वा Disagree मतदान गर्नुहोस्।',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                context,
                MaterialPageRoute(
               builder: (context) => LoanVotingPage(
               uid: uid,
                ),
               ),
              );
             },
            ),
          ),
                      Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance_wallet),
              ),
              title: const Text(
                'खर्च प्रस्ताव मतदान',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'संस्थाको खर्च प्रस्तावमा स्वीकृत वा अस्वीकृत मत दिनुहोस्।',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExpenseWithdrawalVotingPage(
                      uid: uid,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LoanVotingPage extends StatelessWidget {
  final String uid;

  const LoanVotingPage({
    super.key,
    required this.uid,
  });

  Future<void> _submitVote(
    BuildContext context,
    String loanId,
    bool agree,
  ) async {
    try {
      await LoanService().castVote(
        loanId: loanId,
        voterUid: uid,
        agree: agree,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('तपाईंको मतदान सफल भयो।'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('मतदान हुन सकेन: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ऋण मतदान'),
      ),
      body: StreamBuilder(
        stream: LoanService().watchVotingLoans(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('ऋण आवेदन लोड हुन सकेन।'),
            );
          }

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final loans = snapshot.data?.docs ?? [];

          if (loans.isEmpty) {
            return const Center(
              child: Text(
                'हाल मतदान गर्नुपर्ने ऋण आवेदन छैन।',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: loans.length,
            itemBuilder: (context, index) {
              final doc = loans[index];
              final data = doc.data();

              final voters =
                  List<Map<String, dynamic>>.from(
                (data['voters'] ?? []).map(
                  (item) => Map<String, dynamic>.from(item),
                ),
              );

              final myVoters = voters
                  .where((voter) => voter['uid'] == uid)
                  .toList();

              final myVote = myVoters.isNotEmpty
                  ? (myVoters.first['vote'] ?? 'pending')
                      .toString()
                  : 'not_found';

              final round =
                  (data['votingRound'] ?? 1).toString();

              final deadline = data['votingDeadline'];

              final expired = deadline is Timestamp &&
                  DateTime.now().isAfter(deadline.toDate());

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['memberName'] ?? 'सदस्य')
                            .toString(),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),

                      Text(
                        'आवेदन रकम: रु. ${data['requestedAmount'] ?? 0}',
                      ),
                      const SizedBox(height: 6),

                      Text(
                        'ऋणको उद्देश्य: ${data['purpose'] ?? '-'}',
                      ),
                      const SizedBox(height: 6),

                      Text('मतदान चरण: $round'),

                      const SizedBox(height: 8),

                      Text(
                        'सहमति: ${data['yesVotes'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Text(
                        'असहमति: ${data['noVotes'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (myVote == 'pending' && !expired) ...[
                        const Text(
                          'यस ऋण आवेदनमा आफ्नो मत दिनुहोस्:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _submitVote(
                                    context,
                                    doc.id,
                                    true,
                                  );
                                },
                                icon: const Icon(
                                  Icons.check_circle,
                                ),
                                label: const Text('सहमत'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _submitVote(
                                    context,
                                    doc.id,
                                    false,
                                  );
                                },
                                icon: const Icon(
                                  Icons.cancel,
                                ),
                                label: const Text('असहमत'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (myVote == 'agree') ...[
                        const Text(
                          'तपाईंको मत: सहमत',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (myVote == 'disagree') ...[
                        const Text(
                          'तपाईंको मत: असहमत',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (expired) ...[
                        const Text(
                          'मतदानको समयसीमा सकिएको छ। Admin को निर्णय पर्खनुहोस्।',
                          style: TextStyle(
                            color: Colors.orange,
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'तपाईं यस आवेदनको मतदानकर्ता हुनुहुन्न।',
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class DashboardContent extends StatefulWidget {

  final bool memberOnly;
  final String memberName;
  final String uid;

  const DashboardContent({
  super.key,
  this.memberOnly = false,
  this.memberName = '',
  this.uid = '',
});

  static const List<String> names = [
    'कमला देउजा',
    'हरि कुमार चौहान',
    'बाल कुमार चौहान',
    'चन्द्र बहादुर चौहान',
    'टिकाराम चौहान',
    'उदय चौहान',
  ];

  static const List<String> photos = [
    'assets/member1.jpg',
    'assets/member2.jpg',
    'assets/member3.jpg',
    'assets/member4.jpg',
    'assets/member5.jpg',
    'assets/member6.jpg',
  ];

  static const List<String> backgrounds = [
    'assets/atm_member1.jpg',
    'assets/atm_member2.jpg',
    'assets/atm_member3.jpg',
    'assets/atm_member4.jpg',
    'assets/atm_member5.jpg',
    'assets/atm_member6.jpg',
  ];
    
  @override
  State<DashboardContent> createState() => _DashboardContentState();
}


class _DashboardContentState extends State<DashboardContent> {
  final MonthlySavingsService _savingsService = MonthlySavingsService();
    
 final LoanService _loanService = LoanService();
    
Future<int> _getMemberSavings(String memberUid) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('monthly_savings')
      .where('memberUid', isEqualTo: memberUid)
      .get();

  int total = 0;

  for (final doc in snapshot.docs) {
    final data = doc.data();
    total += (data['paidAmount'] as num?)?.toInt() ?? 0;
  }

  return total;
}

@override
  Widget build(BuildContext context) {

    final String normalizedMemberName =
    widget.memberName.trim().replaceAll(RegExp(r'\s+'), '');

final int ownIndex = DashboardContent.names.indexWhere(
  (name) =>
      name.trim().replaceAll(RegExp(r'\s+'), '') ==
      normalizedMemberName,
);
    final int safeIndex = ownIndex < 0 ? 0 : ownIndex;

    final List<int> otherMembers = List.generate(
  DashboardContent.names.length,
  (index) => index,
).where((index) => index != safeIndex).toList();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance.collection('member').snapshots(),
  builder: (context, memberSnapshot) {
    if (memberSnapshot.hasError) {
      return const Center(child: Text('सदस्य विवरण लोड भएन।'));
    }
    if (!memberSnapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final memberUidByName = <String, String>{
      for (final doc in memberSnapshot.data!.docs)
        doc.data()['name']
            .toString()
            .trim()
            .replaceAll(RegExp(r'\s+'), ''): doc.id,
    };

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _savingsService.watchAllRecords(),
      builder: (context, savingsSnapshot) {
        if (savingsSnapshot.hasError) {
          return const Center(child: Text('बचत विवरण लोड भएन।'));
        }
        if (!savingsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final savingsTotals = <String, int>{};
        final insuranceTotals = <String, int>{};

        for (final doc in savingsSnapshot.data!.docs) {
          final data = doc.data();
          final uid = data['memberUid']?.toString() ?? '';

          savingsTotals[uid] =
              (savingsTotals[uid] ?? 0) +
              ((data['savingsPaid'] as num?)?.toInt() ?? 0);

          insuranceTotals[uid] =
              (insuranceTotals[uid] ?? 0) +
              ((data['insurancePaid'] as num?)?.toInt() ?? 0);
        }

  final ownSavings = savingsTotals[widget.uid] ?? 0;
final ownInsurance = insuranceTotals[widget.uid] ?? 0;

// संस्थाका ६ सदस्यको जम्मा बचत
final institutionSavings = savingsTotals.values.fold<int>(
  0,
  (total, amount) => total + amount,
);
// संस्थाका ६ सदस्यको जम्मा बीमा
final institutionInsurance = insuranceTotals.values.fold<int>(
  0,
  (total, amount) => total + amount,
);
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('fund_transactions')
      .snapshots(),
  builder: (context, fundSnapshot) {
    if (fundSnapshot.hasError) {
      return const Center(
        child: Text('कोषको जरिमाना विवरण लोड भएन।'),
      );
    }

    if (!fundSnapshot.hasData) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    int savingsPenaltyTotal = 0;
int insurancePenaltyTotal = 0;
int totalExpenses = 0;

for (final doc in fundSnapshot.data!.docs) {
  final data = doc.data();
  if (data['isTest'] == true) continue;
  final amount = (data['amount'] as num?)?.toInt() ?? 0;

  if (data['fundType'] == 'savings') {
    savingsPenaltyTotal += amount;
  } else if (data['fundType'] == 'insurance') {
    insurancePenaltyTotal += amount;
  } else if (data['fundType'] == 'expense' &&
      data['category'] == 'expense_withdrawal' &&
      data['status'] == 'disbursed') {
    totalExpenses += amount;
  }
}

      
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('loan_installments')
      .where('status', isEqualTo: 'approved')
      .snapshots(),
  builder: (context, installmentSnapshot) {
    if (installmentSnapshot.hasError) {
      return const Center(
        child: Text('किस्ताको ब्याज विवरण लोड भएन।'),
      );
    }

    if (!installmentSnapshot.hasData) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    int loanInterestIncome = 0;

    for (final doc in installmentSnapshot.data!.docs) {
      final data = doc.data();

      if (data['isTest'] == true) continue;

      loanInterestIncome +=
          (data['interestPaid'] as num?)?.toInt() ?? 0;
    }

    final totalInstitutionSavings =
    institutionSavings +
    savingsPenaltyTotal +
    loanInterestIncome -
    totalExpenses;

    final totalInstitutionInsurance =
        institutionInsurance + insurancePenaltyTotal;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _loanService.watchActiveLoans(),
      builder: (context, loanSnapshot) {
            
    if (loanSnapshot.hasError) {
      return const Center(
        child: Text('ऋण विवरण लोड भएन।'),
      );
    }

    if (!loanSnapshot.hasData) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final loanTotals = <String, int>{};

    for (final doc in loanSnapshot.data!.docs) {
      final data = doc.data();
      final memberUid = data['memberUid']?.toString() ?? '';

      final outstanding =
          data['outstandingPrincipal'] ??
          data['remainingPrincipal'] ??
          data['disbursedAmount'] ??
          data['approvedAmount'] ??
          0;

      loanTotals[memberUid] =
          (loanTotals[memberUid] ?? 0) +
          ((outstanding as num).toInt());
    }
      // संस्थाको कुल बाँकी ऋण साँवा
final totalOutstandingLoans =
    loanTotals.values.fold<int>(
  0,
  (total, amount) => total + amount,
);

// संस्थाको उपलब्ध कोष
final availableInstitutionFund =
    totalInstitutionSavings - totalOutstandingLoans > 0
        ? totalInstitutionSavings - totalOutstandingLoans
        : 0;

    return ListView(
      padding: const EdgeInsets.all(14),
  children: [
    // Welcome message
     
          DashboardAnniversaryBanner(
  memberName: widget.memberName.isEmpty
      ? DashboardContent.names[safeIndex]
      : widget.memberName,
),
const SizedBox(height: 16),

        const SizedBox(height: 20),

        // Main ATM card for the logged-in member
        _DashboardAtmCard(
  name: DashboardContent.names[safeIndex],
  photo: DashboardContent.photos[safeIndex],
  background: DashboardContent.backgrounds[safeIndex],savings: 'रु. $ownSavings',
  loan: 'रु. ${loanTotals[widget.uid] ?? 0}',
  large: true,
),

        
const SizedBox(height: 14),

Center(
  child: Container(
    width: 300,
    padding: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 14,
    ),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF102A43),
          Color(0xFF245B4A),
          Color(0xFFB88632),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: const Color(0xFFFFD166),
        width: 1.5,
      ),
      boxShadow: const [
        BoxShadow(
          color: Colors.black26,
          blurRadius: 9,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        const Text(
          'संस्थाको कुल बचत',
          style: TextStyle(
            color: Color(0xFFFFE7A0),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'रु. $totalInstitutionSavings',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  ),
),

const SizedBox(height: 22),
const Text(
  'सेवाहरु',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 10),

Row(
  children: [
    Expanded(
      child: SummaryCard(
        title: 'कुल बचत',
        amount: 'रु. $ownSavings',
        icon: Icons.savings,
        color: const Color(0xFF167D46),
      ),
    ),
      
    const SizedBox(width: 8),
    Expanded(
      child: SummaryCard(
        title: 'बिमा',
        amount: 'रु. $ownInsurance',
        icon: Icons.health_and_safety_outlined,
        color: const Color(0xFF2469B3),
      ),
    ),
  ],
),
      const SizedBox(height: 12),

Row(
  children: [
    Expanded(
      child: SummaryCard(
        title: 'संस्थाको उपलब्ध कोष',
amount: 'रु. $availableInstitutionFund',
        icon: Icons.account_balance,
        color: const Color(0xFF167D46),
      ),
    ),
      
    const SizedBox(width: 8),
    Expanded(
      child: SummaryCard(
        title: 'संस्थाको कुल बीमा',
        amount: 'रु. $totalInstitutionInsurance',
        icon: Icons.health_and_safety,
        color: const Color(0xFF2469B3),
      ),
    ),
  ],
),
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      
child: SummaryCard(
  title: 'मासिक भुक्तानी',
  amount: 'भुक्तानी गर्नुहोस्',
  icon: Icons.calendar_month,
  color: const Color(0xFF8A54B8),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentOptionsPage(
          memberName: widget.memberName,
          uid: widget.uid,
        ),
      ),
    );
  },
),

    ),
    const SizedBox(width: 8),
    Expanded(
      child: SummaryCard(
        title: 'Donate गर्नुहोस्',
        amount: 'चन्दा / दान',
        icon: Icons.volunteer_activism,
        color: const Color(0xFFE28A22),
      ),
    ),
    ],
),

const SizedBox(height: 10),

Row(
  children: [
    Expanded(
      child: SummaryCard(
        title: 'भुक्तानी ढिलाइ सूचना',
        amount: 'जानकारी पेश गर्नुहोस्',
        icon: Icons.event_note,
        color: const Color(0xFFE28A22),
        onTap: () {
          final today =
              NepaliDateTime.fromDateTime(DateTime.now());

          if (today.day < 1 || today.day > 9) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'यो सुविधा प्रत्येक महिनाको १ देखि ९ गतेसम्म मात्र उपलब्ध छ।',
                ),
              ),
            );
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LatePaymentNoticePage(
                memberName: widget.memberName,
                uid: widget.uid,
              ),
            ),
          );
        },
      ),
    ),
  ],
),

const SizedBox(height: 22),
const Text(
  'अन्य सदस्यहरू',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        // Remaining five members
        ...otherMembers.map((index) {
  return _DashboardAtmCard(
    name: DashboardContent.names[index],
    photo: DashboardContent.photos[index],
    background: DashboardContent.backgrounds[index],
    savings: 'रु. ${savingsTotals[memberUidByName[
  DashboardContent.names[index]
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
] ?? ''] ?? 0}',
    loan: 'रु. ${loanTotals[memberUidByName[
  DashboardContent.names[index]
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
] ?? ''] ?? 0}',
    large: false,
  );
}),

        const SizedBox(height: 20),
        const Text(
          'मुख्य सेवाहरू',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const ServiceTile(
          icon: Icons.savings_outlined,
          title: 'मासिक बचत',
          subtitle: 'बचत तथा योगदान विवरण',
        ),
        const ServiceTile(
          icon: Icons.request_quote_outlined,
          title: 'ऋण व्यवस्थापन',
          subtitle: 'ऋण तथा किस्ता विवरण',
        ),
       
ServiceTile(
  icon: Icons.health_and_safety_outlined,
  title: 'बीमा',
  subtitle: 'बीमा कोष, दाबी फाराम तथा अभिलेख',
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InsuranceManagementPage(
          uid: widget.uid,
          memberName: widget.memberName,
          isAdmin: !widget.memberOnly,
        ),
      ),
    );
  },
),
         ServiceTile(
  icon: Icons.receipt_long_outlined,
  title: 'रिपोर्ट तथा विवरण',
  subtitle: 'आर्थिक कारोबारको विवरण',
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FinancialReportPage(
          memberUid: widget.uid,
          memberName: widget.memberName,
          role: widget.memberOnly ? 'member' : 'admin',
        ),
      ),
    );
  },
),
          ],
        );
      },
    );
        },
      );
     },
    );
      },
  );
    },
  );
 }
}

class _DashboardAtmCard extends StatelessWidget {
  final String name;
  final String photo;
  final String background;
  final String savings;
  final String loan;
  final bool large;
  final bool redacted;

  const _DashboardAtmCard({
    required this.name,
    required this.photo,
    required this.background,
    required this.savings,
    required this.loan,
    required this.large,
    this.redacted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: large ? 155 : 120,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF102A43),
        image: DecorationImage(
          image: AssetImage(background),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.48),
            BlendMode.darken,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(large ? 28 : 22),
                  child: Image.asset(
                    photo,
                    width: large ? 56 : 44,
                    height: large ? 56 : 44,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: large ? 17 : 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.credit_card,
                  color: Color(0xFFFFD166),
                  size: 27,
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'कुल बचत',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        savings,
                        style: TextStyle(
                          color: redacted ? Colors.redAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: large ? 16 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'कुल बाँकी ऋण',
                        style: TextStyle(
                          color: Color(0xFFFFB4A9),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        loan,
                        style: TextStyle(
                          color: redacted ? Colors.redAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: large ? 16 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _MemberCard extends StatelessWidget {
  final String name;
  final String photo;
  final String background;

  const _MemberCard({
    required this.name,
    required this.photo,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        color: navy,
        border: Border.all(color: gold.withValues(alpha: 0.55)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            background,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: navy);
            },
          ),
          ColoredBox(color: navy.withValues(alpha: 0.66)),
          Row(
            children: [
              const SizedBox(width: 15),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: gold, width: 2),
                ),
                child: ClipOval(
                  child: Image.asset(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.person,
                        color: gold,
                        size: 42,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'पारिवारिक बचत कोष',
                      style: TextStyle(
                        color: goldLight,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'सदस्य कार्ड',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 15),
                child: Icon(
                  Icons.contactless,
                  color: gold,
                  size: 26,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF263238),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

   class ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const ServiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    
final bool isReport = title == 'रिपोर्ट तथा विवरण';

return Card(
  color: isReport
      ? const Color(0xFF17365D)
      : Colors.white,
  elevation: isReport ? 4 : 0,
  margin: const EdgeInsets.only(bottom: 10),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(15),
    side: isReport
        ? const BorderSide(
            color: Color(0xFFFFB02E),
            width: 1.5,
          )
        : BorderSide.none,
  ),
  child: ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 5,
    ),
    leading: Icon(
      icon,
      color: isReport
          ? const Color(0xFFFFC857)
          : const Color(0xFF167D46),
      size: 30,
    ),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: isReport
            ? Colors.white
            : Colors.black87,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        color: isReport
            ? Colors.white70
            : Colors.black54,
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: isReport
          ? const Color(0xFFFFC857)
          : Colors.black54,
    ),
  ),
);

  }
}

class MemberProfilePage extends StatefulWidget {
  final String uid;

  const MemberProfilePage({
    super.key,
    required this.uid,
  });

  @override
  State<MemberProfilePage> createState() =>
      _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
    
      final TextEditingController _mobileController =
      TextEditingController();
  final TextEditingController _dateOfBirthController =
      TextEditingController();
  final TextEditingController _addressController =
      TextEditingController();
  final TextEditingController _occupationController =
      TextEditingController();
  final TextEditingController _citizenshipController =
      TextEditingController();

  bool _profileFieldsLoaded = false;
  bool _isSavingProfile = false;
  bool _biometricEnabled = false;
  bool _biometricBusy = false;
    
  final List<Map<String, TextEditingController>>
    _familyMemberControllers = [];
    
    void _addFamilyMember() {
  setState(() {
    _familyMemberControllers.add({
      'name': TextEditingController(),
      'relation': TextEditingController(),
      'dateOfBirth': TextEditingController(),
    });
  });
}
    
  Future<void> _saveProfileData({
    required String mobileNumber,
    required String dateOfBirth,
    required String address,
    required String occupation,
    required String citizenshipNumber,
    required List<Map<String, dynamic>> familyMembers,
  }) async {
    await FirebaseFirestore.instance
        .collection('member')
        .doc(widget.uid)
        .set({
      'mobileNumber': mobileNumber.trim(),
      'dateOfBirth': dateOfBirth.trim(),
      'address': address.trim(),
      'occupation': occupation.trim(),
      'citizenshipNumber': citizenshipNumber.trim(),
      'familyMembers': familyMembers,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
    
  Future<void> _setBiometric(bool enabled) async {
    if (_biometricBusy) return;
    setState(() => _biometricBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!enabled) {
        await prefs.setBool('biometric_enabled_${widget.uid}', false);
        if (mounted) setState(() => _biometricEnabled = false);
        return;
      }
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) throw Exception('यो मोबाइलले Biometric समर्थन गर्दैन।');
      final available = await auth.getAvailableBiometrics();
      if (available.isEmpty) throw Exception('मोबाइलमा Fingerprint वा Face Unlock सेटअप गरिएको छैन।');
      final authenticated = await auth.authenticate(
        localizedReason: 'Biometric सक्रिय गर्न आफ्नो पहिचान पुष्टि गर्नुहोस्।',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!authenticated) return;
      await prefs.setBool('biometric_enabled_${widget.uid}', true);
      if (mounted) setState(() => _biometricEnabled = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biometric Login सक्रिय भयो।')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Biometric सेट गर्न सकिएन: $e')));
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

      Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null ||
        user.uid != widget.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login विवरण प्रमाणित हुन सकेन।'),
        ),
      );
      return;
    }

    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    final shouldChange = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('पासवर्ड परिवर्तन'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'पुरानो Password',
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty
                          ? 'पुरानो Password राख्नुहोस्।'
                          : null,
                ),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'नयाँ Password',
                  ),
                  validator: (value) =>
                      value == null || value.length < 6
                          ? 'कम्तीमा ६ अक्षर राख्नुहोस्।'
                          : null,
                ),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'नयाँ Password फेरि राख्नुहोस्',
                  ),
                  validator: (value) =>
                      value != newPasswordController.text
                          ? 'दुवै Password मिलेनन्।'
                          : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('रद्द गर्नुहोस्'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('परिवर्तन गर्नुहोस्'),
            ),
          ],
        );
      },
    );

    if (shouldChange != true) {
      oldPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPasswordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      await user.updatePassword(
        newPasswordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password सफलतापूर्वक परिवर्तन भयो।'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final message = e.code == 'wrong-password' ||
              e.code == 'invalid-credential'
          ? 'पुरानो Password मिलेन।'
          : e.code == 'weak-password'
              ? 'नयाँ Password कमजोर छ।'
              : 'Password परिवर्तन हुन सकेन: ${e.message}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटि भयो: $e'),
        ),
      );
    } finally {
      oldPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
  }
    
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
        .collection('member')
        .doc(widget.uid)
        .snapshots(),
            builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

      if (snapshot.hasError || !snapshot.hasData ||
            !snapshot.data!.exists) {
          return const Center(
            child: Text('सदस्य विवरण लोड हुन सकेन।'),
          );
        }

        final data = snapshot.data!.data() ?? {};

        if (!_profileFieldsLoaded) {
          _mobileController.text =
              data['mobileNumber']?.toString() ?? '';
          _dateOfBirthController.text =
              toNepaliDigits(data['dateOfBirth']?.toString() ?? '');
          _addressController.text =
              data['address']?.toString() ?? '';
          _occupationController.text =
              data['occupation']?.toString() ?? '';
          _citizenshipController.text =
              data['citizenshipNumber']?.toString() ?? '';

          _profileFieldsLoaded = true;
          SharedPreferences.getInstance().then((prefs) {
            if (mounted) setState(() => _biometricEnabled = prefs.getBool('biometric_enabled_${widget.uid}') ?? false);
          });
        }
        final savedFamilyMembers =
    data['familyMembers'] as List<dynamic>? ?? [];

for (final item in savedFamilyMembers) {
  final familyData = Map<String, dynamic>.from(item as Map);

  _familyMemberControllers.add({
    'name': TextEditingController(
      text: familyData['name']?.toString() ?? '',
    ),
    'relation': TextEditingController(
      text: familyData['relation']?.toString() ?? '',
    ),
    'dateOfBirth': TextEditingController(
      text: toNepaliDigits(familyData['dateOfBirth']?.toString() ?? ''),
    ),
  });
}

        final name = data['name']?.toString() ?? 'नाम उपलब्ध छैन';
        final role = data['role']?.toString() ?? 'member';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const CircleAvatar(
                radius: 48,
                child: Icon(Icons.person, size: 55),
              ),
              const SizedBox(height: 14),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                role == 'admin' ? 'प्रशासक' : 'सदस्य',
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Login Email'),
                  subtitle: Text(
             data['email']?.toString() ?? 'उपलब्ध छैन',
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('सदस्यको नाम'),
                  subtitle: Text(name),
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'मोबाइल नम्बर',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
  controller: _dateOfBirthController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'जन्म मिति (वि.सं.)',
    hintText: 'पात्रोबाट मिति छान्नुहोस्',
    border: OutlineInputBorder(),
    suffixIcon: Icon(Icons.calendar_month),
  ),
  onTap: () async {
    final pickedDate = await showNepaliDatePicker(
      context: context,
      initialDate: NepaliDateTime.now(),
      firstDate: NepaliDateTime(1970, 2, 5),
      lastDate: NepaliDateTime.now(),
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _dateOfBirthController.text =
            toNepaliDigits(NepaliDateFormat('yyyy-MM-dd').format(pickedDate));
      });
    }
  },
),
              const SizedBox(height: 14),

              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'ठेगाना',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _occupationController,
                decoration: const InputDecoration(
                  labelText: 'पेशा',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _citizenshipController,
                decoration: const InputDecoration(
                  labelText: 'नागरिकता नम्बर',
                  border: OutlineInputBorder(),
                ),
              ),
          const SizedBox(height: 24),

const Text(
  'परिवारका सदस्यहरूको विवरण',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 12),

..._familyMemberControllers.asMap().entries.map((entry) {
  final index = entry.key;
  final controllers = entry.value;

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: controllers['name'],
            decoration: const InputDecoration(
              labelText: 'नाम',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
DropdownButtonFormField<String>(
  value: [
    'बुवा',
    'आमा',
    'श्रीमान्',
    'श्रीमती',
    'छोरा',
    'छोरी',
  ].contains(controllers['relation']!.text)
      ? controllers['relation']!.text
      : null,
  decoration: const InputDecoration(
    labelText: 'नाता',
    border: OutlineInputBorder(),
  ),
  items: [
    'बुवा',
    'आमा',
    'श्रीमान्',
    'श्रीमती',
    'छोरा',
    'छोरी',
  ].map((relation) {
    return DropdownMenuItem<String>(
      value: relation,
      child: Text(relation),
    );
  }).toList(),
  onChanged: (value) {
    controllers['relation']!.text = value ?? '';
  },
),
          const SizedBox(height: 10),
          TextField(
            controller: controllers['dateOfBirth'],
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'जन्म मिति (वि.सं.)',
              hintText: 'पात्रोबाट मिति छान्नुहोस्',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_month),
            ),
            onTap: () async {
              final pickedDate = await showNepaliDatePicker(
             context: context,
             initialDate: NepaliDateTime.now(),
             firstDate: NepaliDateTime(1970, 2, 5),
             lastDate: NepaliDateTime.now(),
              );

              if (pickedDate != null && mounted) {
                controllers['dateOfBirth']!.text =
                    toNepaliDigits(NepaliDateFormat('yyyy-MM-dd').format(pickedDate));
              }
            },
          ),
        ],
      ),
    ),
  );
}).toList(),

Align(
  alignment: Alignment.centerRight,
  child: ElevatedButton.icon(
    onPressed: _addFamilyMember,
    icon: const Icon(Icons.add),
    label: const Text('परिवारको सदस्य थप्नुहोस्'),
  ),
),

const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
  icon: _isSavingProfile
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        )
      : const Icon(Icons.save),
  label: Text(
    _isSavingProfile
        ? 'सुरक्षित हुँदैछ...'
        : 'विवरण सुरक्षित गर्नुहोस्',
  ),
                    
            onPressed: _isSavingProfile
          ? null
          : () async {
    setState(() {
      _isSavingProfile = true;
    });

    try {
      final familyMembers = _familyMemberControllers
    .map((controllers) => {
          'name': controllers['name']!.text.trim(),
          'relation': controllers['relation']!.text.trim(),
          'dateOfBirth':
              toWesternDigits(controllers['dateOfBirth']!.text.trim()),
        })
    .where((member) =>
        member.values.any((value) => value.toString().isNotEmpty))
    .toList();

  await _saveProfileData(
 mobileNumber: _mobileController.text,
 dateOfBirth: toWesternDigits(_dateOfBirthController.text),
 address: _addressController.text,
 occupation: _occupationController.text,
 citizenshipNumber: _citizenshipController.text,
 familyMembers: familyMembers,
                      );

                      if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
  content: Text('विवरण सफलतापूर्वक सुरक्षित भयो।'),
                        ),
                      );
 } catch (e) {
 if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
     content: Text('विवरण सुरक्षित हुन सकेन: $e'),
                      ),
                    );
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isSavingProfile = false;
                      });
                    }
                  }
                  },
                ),
              ),  
            const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _changePassword,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('पासवर्ड परिवर्तन गर्नुहोस्'),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.fingerprint, color: Color(0xFF245B4A)),
                  title: const Text('Biometric Login', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_biometricEnabled ? 'Fingerprint / Face Unlock सक्रिय छ' : 'Fingerprint / Face Unlock निष्क्रिय छ'),
                  value: _biometricEnabled,
                  onChanged: _biometricBusy ? null : _setBiometric,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SimplePage extends StatelessWidget {
  final String title;

  const SimplePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.construction_outlined,
              size: 55,
              color: Color(0xFF167D46),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'यो सुविधा अर्को चरणमा तयार गरिनेछ।',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentOptionsPage extends StatelessWidget {
  final String memberName;
  final String uid;

  const PaymentOptionsPage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मासिक भुक्तानी'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.payment,
                color: Color(0xFF167D46),
                size: 30,
              ),
              title: const Text(
                'भुक्तानी गर्नुहोस्',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('मासिक बचत तथा अन्य भुक्तानी'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentFormPage(
                      memberName: memberName,
                      uid: uid,
                    ),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance,
                color: Color(0xFF2469B3),
                size: 30,
              ),
              title: const Text(
                'भुक्तानी बैंक विवरण',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('बैंक QR तथा Copy गर्न मिल्ने विवरण'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BankPaymentDetailsPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentFormPage extends StatefulWidget {
  final String memberName;
  final String uid;

  const PaymentFormPage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  State<PaymentFormPage> createState() => _PaymentFormPageState();
}

class _PaymentFormPageState extends State<PaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
Stream<QuerySnapshot<Map<String, dynamic>>> _watchMonthlyRecords() {
  return MonthlySavingsService().watchMemberRecords(widget.uid);
}
  final _noteController = TextEditingController();

  String _paymentType = 'full';
  bool _saving = false;
  int _selectedMonthCount = 1;
    
@override
void initState() {
  super.initState();
  _ensureNext12Months();
}

Future<void> _ensureNext12Months() async {
  try {
    final service = MonthlySavingsService();

    final firstUnpaidMonth = await service.findFirstUnpaidMonth(
      memberUid: widget.uid,
      startMonthKey: '2083-07',
    );

    await service.createNext12Months(
      memberUid: widget.uid,
      firstMonthKey: firstUnpaidMonth,
    );
  } catch (e) {
    debugPrint('अर्को १२ महिनाको रेकर्ड तयार गर्न समस्या: $e');
  }
}


int get _calculatedFullAmount {
  return 0;
}
  List<String> _selectedMonths = [];
bool _paymentConsent = false;

  @override
  void dispose() {
    _amountController.dispose();
    _monthController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
if (_paymentType != 'donation' && _selectedMonths.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('कृपया भुक्तानीका लागि कम्तीमा एउटा महिना छान्नुहोस्।'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}

    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
 
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('सही भुक्तानी रकम लेख्नुहोस्।'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // आंशिक भुक्तानीको बाँकी रकम र न्यूनतम रकम जाँच।
    if (_paymentType == 'partial') {
      if (_selectedMonths.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('भुक्तानीका लागि महिना चयन हुन सकेन।'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final monthKey = _selectedMonths.first;

      final recordSnapshot = await FirebaseFirestore.instance
          .collection('monthly_savings')
          .where('memberUid', isEqualTo: widget.uid)
          .where('monthKey', isEqualTo: monthKey)
          .limit(1)
          .get();

      if (recordSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('मासिक रेकर्ड भेटिएन।'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final record = recordSnapshot.docs.first.data();

      final total = (record['totalDue'] as num?)?.toInt() ?? 0;
      final paid = (record['paidAmount'] as num?)?.toInt() ?? 0;
      final insurance = (record['insuranceAmount'] as num?)?.toInt() ?? 300;
      final insurancePaid =
          (record['insurancePaid'] as num?)?.toInt() ?? 0;

      final remaining = (total - paid).clamp(0, total);
      // बीमाको बाँकी रकम र बीमामा लागेको जरिमाना जाँच।
final insuranceRemaining =
    (insurance - insurancePaid).clamp(0, insurance);

final penaltyResult =
    await PenaltyService().calculateMemberPenalty(
  memberUid: widget.uid,
);

final penaltyDetails =
    penaltyResult['penaltyDetailsByMonth']
        as Map<String, dynamic>? ?? {};

final monthPenalty =
    penaltyDetails[monthKey] as Map<String, dynamic>? ?? {};

final insurancePenalty =
    (monthPenalty['insurancePenaltyDue'] as num?)?.toInt() ?? 0;

final minimum = insuranceRemaining > 0
    ? insuranceRemaining + insurancePenalty
    : 50;

if (amount < minimum) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        insuranceRemaining > 0
            ? 'बीमाको बाँकी रकम र जरिमाना सहित कम्तीमा रु. $minimum भुक्तानी गर्नुपर्छ।'
            : 'आंशिक भुक्तानी कम्तीमा रु. ५० हुनुपर्छ।',
      ),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
        final savingsPenalty =
    (monthPenalty['savingsPenaltyDue'] as num?)?.toInt() ?? 0;

final totalPenalty = insurancePenalty + savingsPenalty;

final maximum = remaining + insuranceRemaining + totalPenalty;

if (amount >= maximum) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'यो रकम पूर्ण भुक्तानीयोग्य रकम हो। कृपया पूर्ण भुक्तानी छान्नुहोस्।',
      ),
      backgroundColor: Colors.orange,
    ),
  );
  return;
}
    }
    setState(() => _saving = true);

    try {
      final now = DateTime.now();

final adDate =
    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

// AD मितिलाई BS मितिमा रूपान्तरण
final bsNow = NepaliDateTime.fromDateTime(now);

const bsMonths = [
  'बैशाख',
  'जेठ',
  'असार',
  'साउन',
  'भदौ',
  'असोज',
  'कार्तिक',
  'मंसिर',
  'पुष',
  'माघ',
  'फागुन',
  'चैत',
];

const weekdays = [
  'आइतबार',
  'सोमबार',
  'मंगलबार',
  'बुधबार',
  'बिहिबार',
  'शुक्रबार',
  'शनिबार',
];

final bsDate =
    '${bsNow.year} साल ${bsMonths[bsNow.month - 1]} ${bsNow.day} गते ${weekdays[bsNow.weekday - 1]}';

      // BS मिति र महिना हाल प्रयोगकर्ताले भरेको मानबाट लिइन्छ।
      // स्वचालित BS/AD रूपान्तरण अर्को चरणमा जोडिनेछ।

      await PaymentService().submitPayment(
        memberUid: widget.uid,
        memberName: widget.memberName,
        paymentType: _paymentType,
        amount: amount,
        bsDate: bsDate,
      adDate: adDate,
 monthKeys: _paymentType == 'donation'
    ? []
    : List<String>.from(_selectedMonths),
        note: _noteController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('भुक्तानी स्वीकृतिका लागि पठाइयो।'),
          backgroundColor: Colors.green,
        ),
      );

      _amountController.clear();
      _monthController.clear();
      _noteController.clear();
   
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('भुक्तानी पठाउन असफल: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('मासिक भुक्तानी')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            
              Text('सदस्य: ${widget.memberName}'),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: const InputDecoration(
                labelText: 'भुक्तानीको प्रकार',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'full',
                  child: Text('पूर्ण मासिक भुक्तानी'),
                ),
                DropdownMenuItem(
                  value: 'partial',
                  child: Text('आंशिक भुक्तानी'),
                ),
                DropdownMenuItem(
                  value: 'donation',
                  child: Text('चन्दा / दान'),
                ),
              ],
              onChanged: (value) {
  if (value == null) return;

  setState(() {
    _paymentType = value;
    _selectedMonths.clear();
    _selectedMonthCount = 0;
    _amountController.clear();

        if (_paymentType == 'donation') {
      _monthController.clear();
    }
  });
},
 ),
const SizedBox(height: 14),

if (_paymentType == 'full' || _paymentType == 'partial')
  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: MonthlySavingsService().watchMemberRecords(widget.uid),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'मासिक रेकर्ड पढ्न समस्या भयो।',
          style: TextStyle(color: Colors.red),
        );
      }

      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final records = snapshot.data!.docs
          .map((doc) => doc.data())
          .where((data) =>
              (data['monthKey']?.toString() ?? '').isNotEmpty)
          .toList()
        ..sort((a, b) => (a['monthKey'] as String)
            .compareTo(b['monthKey'] as String));

      final unpaidRecords = records.where((data) {
        final total = (data['totalDue'] as num?)?.toInt() ?? 0;
        final paid = (data['paidAmount'] as num?)?.toInt() ?? 0;
        return total > paid && total > 0;
      }).toList();

      final availableKeys = unpaidRecords
          .map((data) => data['monthKey'].toString())
          .toList()
        ..sort();

      // आंशिक भुक्तानीमा पहिलो बाँकी महिना स्वतः चयन गर्ने।
      if (_paymentType == 'partial' && availableKeys.isNotEmpty) {
        final firstKey = availableKeys.first;

        if (_selectedMonths.length != 1 ||
            _selectedMonths.first != firstKey) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _paymentType != 'partial') return;

            if (_selectedMonths.length != 1 ||
                _selectedMonths.first != firstKey) {
              setState(() {
                _selectedMonths = [firstKey];
              });
            }
          });
        }
      }

      final validSelected = _selectedMonths
          .where((key) => availableKeys.contains(key))
          .toList();

      final selectedPrincipal = records
    .where((data) => validSelected.contains(
          data['monthKey'].toString(),
        ))
    .fold<int>(0, (sum, data) {
  final total = (data['totalDue'] as num?)?.toInt() ?? 0;
  final paid = (data['paidAmount'] as num?)?.toInt() ?? 0;

  return sum + (total - paid).clamp(0, total);
});

      if (availableKeys.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'हाल कुनै महिनाको भुक्तानी बाँकी छैन।',
            style: TextStyle(color: Colors.green),
          ),
        );
      }

      // आंशिक भुक्तानी: महिना स्वतः चयन, Dropdown नदेखाउने।
      // आंशिक भुक्तानी: महिना स्वतः चयन, Dropdown नदेखाउने।
if (_paymentType == 'partial') {
  final key = availableKeys.first;
  final record = unpaidRecords.firstWhere(
    (data) => data['monthKey'].toString() == key,
  );

  final total = (record['totalDue'] as num?)?.toInt() ?? 0;
  final paid = (record['paidAmount'] as num?)?.toInt() ?? 0;
  final remaining = (total - paid).clamp(0, total).toInt();

  return FutureBuilder<Map<String, dynamic>>(
    future: PenaltyService().calculateMemberPenalty(
      memberUid: widget.uid,
    ),
    builder: (context, penaltySnapshot) {
      if (penaltySnapshot.hasError) {
        return const Text(
          'जरिमाना विवरण पढ्न समस्या भयो।',
          style: TextStyle(color: Colors.red),
        );
      }

      if (!penaltySnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final penaltyMap =
          penaltySnapshot.data!['netPenaltyByMonth'] as Map;

      final penalty =
          (penaltyMap[key] as num?)?.toInt() ?? 0;

      final totalPayable = remaining + penalty;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'आंशिक भुक्तानीको महिना (स्वतः चयन)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              key,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text('मासिक रकम: रु. $total'),
            Text('पहिले तिरेको: रु. $paid'),
            Text(
              'बाँकी साँवा: रु. $remaining',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'बाँकी जरिमाना: रु. $penalty',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Text(
              'कुल तिर्नुपर्ने: रु. $totalPayable',
              style: const TextStyle(
                fontSize: 17,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'माथिको कुल रकमभित्र रहेर भुक्तानी रकम लेख्नुहोस्।',
            ),
          ],
        ),
      );
    },
  );
}

      // पूर्ण भुक्तानी: सदस्यले अन्तिम महिना छान्ने।
      final monthOptions = availableKeys;

      final validFullSelection = _selectedMonths
          .where((key) => monthOptions.contains(key))
          .toList();

      return FutureBuilder<Map<String, dynamic>>(
        future: PenaltyService().calculateMemberPenalty(
          memberUid: widget.uid,
        ),
        builder: (context, penaltySnapshot) {
          if (penaltySnapshot.hasError) {
            return const Text(
              'जरिमाना विवरण पढ्न समस्या भयो।',
              style: TextStyle(color: Colors.red),
            );
          }

          if (!penaltySnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final penaltyMap =
              penaltySnapshot.data!['netPenaltyByMonth'] as Map;

          int selectedPrincipal = 0;
          int selectedPenalty = 0;

          for (final data in unpaidRecords) {
            final key = data['monthKey'].toString();

            if (!validFullSelection.contains(key)) continue;

            final total =
                (data['totalDue'] as num?)?.toInt() ?? 0;
            final paid =
                (data['paidAmount'] as num?)?.toInt() ?? 0;

            selectedPrincipal +=
                (total - paid).clamp(0, total).toInt();

            selectedPenalty +=
                (penaltyMap[key] as num?)?.toInt() ?? 0;
          }

          final selectedTotal =
              selectedPrincipal + selectedPenalty;
            if (_paymentType == 'full') {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _paymentType != 'full') return;

    final amountText = validFullSelection.isEmpty
        ? ''
        : selectedTotal.toString();

    if (_amountController.text != amountText) {
      _amountController.text = amountText;
    }
  });
}

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'पूर्ण भुक्तानीका लागि अन्तिम महिना छान्नुहोस्',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: validFullSelection.isEmpty
                    ? null
                    : validFullSelection.last,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'बाँकी महिना',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('महिना छान्नुहोस्'),
                items: monthOptions.map((key) {
                  final record = unpaidRecords.firstWhere(
                    (data) => data['monthKey'].toString() == key,
                  );

                  final total =
                      (record['totalDue'] as num?)?.toInt() ?? 0;
                  final paid =
                      (record['paidAmount'] as num?)?.toInt() ?? 0;
                  final penalty =
                      (penaltyMap[key] as num?)?.toInt() ?? 0;

                  final remaining =
                      (total - paid).clamp(0, total).toInt();

                  return DropdownMenuItem<String>(
                    value: key,
                    child: Text(
                      '$key — जम्मा रु. ${remaining + penalty}',
                    ),
                  );
                }).toList(),
                onChanged: (key) {
                  if (key == null) return;

                  final index = monthOptions.indexOf(key);
                  final selectedKeys =
                      monthOptions.take(index + 1).toList();

                  setState(() {
                    _selectedMonths = selectedKeys;
                    _amountController.clear();
                  });
                },
              ),
              const SizedBox(height: 10),
              if (validFullSelection.isNotEmpty) ...[
                Text(
                  'छानिएका महिना: ${validFullSelection.join(', ')}',
                ),
                const SizedBox(height: 6),
                Text('बाँकी साँवा: रु. $selectedPrincipal'),
                Text(
                  'बाँकी जरिमाना: रु. $selectedPenalty',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(),
                Text(
                  'कुल भुक्तानी रकम: रु. $selectedTotal',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                 'यो रकम पूर्ण भुक्तानीका लागि आवश्यक रकम हो।',
                ),
              ],
            ],
          );
        },
      );
    },
  ),

                    TextFormField(
              controller: _amountController,
              readOnly: _paymentType == 'full',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'भुक्तानी रकम (रु.)',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final amount = int.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'शून्यभन्दा बढी रकम लेख्नुहोस्।';
                }
                return null;
              },
            ),

 
            if (_paymentType == 'donation') ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _monthController,
                decoration: const InputDecoration(
                  labelText: 'चन्दा/दान मिति (BS)',
                  border: OutlineInputBorder(),
                  helperText: 'चन्दा/दानको मिति लेख्नुहोस्।',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'BS मिति लेख्नुहोस्।';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'कैफियत (ऐच्छिक)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _saving ? null : _submitPayment,
              icon: const Icon(Icons.send),
              label: Text(
                _saving ? 'पठाउँदै...' : 'स्वीकृतिका लागि पठाउनुहोस्',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class LoanApplicationPage extends StatefulWidget {
  final String memberName;
  final String uid;

  const LoanApplicationPage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  State<LoanApplicationPage> createState() => _LoanApplicationPageState();
}

class _LoanApplicationPageState extends State<LoanApplicationPage> {
    final LoanService _loanService = LoanService();

final TextEditingController _amountController =
    TextEditingController();

final TextEditingController _purposeController =
    TextEditingController();

final TextEditingController _bsDateController =
    TextEditingController();

final TextEditingController _adDateController =
    TextEditingController();
    int _selectedDurationMonths = 1;

  int get _enteredLoanAmount => int.tryParse(_amountController.text.trim()) ?? 0;
  int get _maximumLoanDuration => LoanService.maxDurationForAmount(_enteredLoanAmount);
  double get _monthlyLoanRate => LoanService.monthlyRateForAmount(_enteredLoanAmount);

  void _onLoanAmountChanged(String value) {
    final amount = int.tryParse(value.trim()) ?? 0;
    final maxMonths = amount > 0 ? LoanService.maxDurationForAmount(amount) : 12;
    setState(() {
      if (_selectedDurationMonths > maxMonths) _selectedDurationMonths = maxMonths;
    });
  }

final Set<String> _selectedGuarantorUids = {};

bool _isSubmitting = false;
int _eligibleLoanAmount = 0;
bool _isLoadingEligibleAmount = true;
String? _loanAmountError;

@override
void initState() {
  super.initState();

  final now = DateTime.now();
  final bsNow = NepaliDateTime.fromDateTime(now);

  const bsMonths = [
    'बैशाख', 'जेठ', 'असार', 'साउन',
    'भदौ', 'असोज', 'कार्तिक', 'मंसिर',
    'पुष', 'माघ', 'फागुन', 'चैत',
  ];

  const weekdays = [
    'आइतबार', 'सोमबार', 'मंगलबार', 'बुधबार',
    'बिहिबार', 'शुक्रबार', 'शनिबार',
  ];

  _bsDateController.text = toNepaliDigits(
      '${bsNow.year}/${bsNow.month.toString().padLeft(2, '0')}/${bsNow.day.toString().padLeft(2, '0')} '
      '(${bsMonths[bsNow.month - 1]} ${bsNow.day} गते, ${weekdays[bsNow.weekday - 1]})');

  _adDateController.text =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  _loadEligibleLoanAmount();
}

Future<void> _loadEligibleLoanAmount() async {
  try {
    final amount =
        await FundService().calculateLoanEligibleAmount();

    if (!mounted) return;

    setState(() {
      _eligibleLoanAmount = amount;
      _isLoadingEligibleAmount = false;
      _loanAmountError = null;
    });
} catch (e) {
  debugPrint('Loan eligibility error: $e');

  if (!mounted) return;

  setState(() {
    _loanAmountError = 'त्रुटि: $e';
    _isLoadingEligibleAmount = false;
  });
}
}

@override
void dispose() {
  _amountController.dispose();
  _purposeController.dispose();
  _bsDateController.dispose();
  _adDateController.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('member')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
   child: Text('सदस्य विवरण लोड हुन सकेन।'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
 child: CircularProgressIndicator(),
          );
        }

        final members = snapshot.data!.docs.where((doc) {
          return doc.id != widget.uid;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
              // उपलब्ध ऋण रकम
Container(
  padding: const EdgeInsets.all(16),
  margin: const EdgeInsets.only(bottom: 18),
  decoration: BoxDecoration(
    color: Colors.blue.withOpacity(0.08),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: Colors.blueAccent),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'तपाईंले लिन पाउने अधिकतम ऋण रकम',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      if (_isLoadingEligibleAmount)
        const CircularProgressIndicator()
      else if (_loanAmountError != null)
        Text(
          _loanAmountError!,
          style: const TextStyle(color: Colors.red),
        )
      else
        Text(
          'रु. ${_eligibleLoanAmount.toString()}',
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: Colors.green,
          ),
        ),
    ],
  ),
),
            const Text(
              'ऋण आवेदन फाराम',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),

            Text(
              'आवेदक: ${widget.memberName}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'आवश्यक ऋण रकम (रु.)',
                prefixIcon: Icon(Icons.currency_rupee),
                border: OutlineInputBorder(),
              ),
              onChanged: _onLoanAmountChanged,
            ),
            const SizedBox(height: 8),
            if (_enteredLoanAmount > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'मासिक ब्याजदर: ${_monthlyLoanRate.toStringAsFixed(2)}%  •  अधिकतम अवधि: $_maximumLoanDuration महिना',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
              ),
            const SizedBox(height: 14),

DropdownButtonFormField<int>(
  value: _selectedDurationMonths,
  decoration: const InputDecoration(
    labelText: 'ऋण चुक्ता गर्ने अवधि',
    prefixIcon: Icon(Icons.calendar_month),
    border: OutlineInputBorder(),
  ),
  items: List.generate(_enteredLoanAmount > 0 ? _maximumLoanDuration : 12, (index) {
    final months = index + 1;
    return DropdownMenuItem<int>(
      value: months,
      child: Text('$months महिना'),
    );
  }),
  onChanged: (value) {
    if (value != null) {
      setState(() {
        _selectedDurationMonths = value;
      });
    }
  },
),

            TextField(
              controller: _purposeController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ऋण लिनुको कारण / प्रयोजन',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            TextField(
  controller: _bsDateController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'आवेदन मिति (वि.सं.)',
    hintText: 'स्वतः भरिनेछ',
    prefixIcon: Icon(Icons.calendar_month),
    border: OutlineInputBorder(),
  ),
),
const SizedBox(height: 14),

TextField(
  controller: _adDateController,
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'आवेदन मिति (ई.सं.)',
    hintText: 'स्वतः भरिनेछ',
    prefixIcon: Icon(Icons.date_range),
    border: OutlineInputBorder(),
  ),
),

const SizedBox(height: 22),

const Text(
  'मतदानमा स्वतः सहभागी हुने पाँच सदस्य',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 5),

const Text(
  'तपाईं बाहेक बाँकी पाँचै सदस्य स्वतः मतदानकर्ता हुनुहुनेछ।',
  style: TextStyle(fontSize: 13),
),
const SizedBox(height: 10),

...members.map((doc) {
  final data = doc.data();
  final name = (data['name'] ?? '').toString();

  return ListTile(
    leading: const Icon(
      Icons.how_to_vote_outlined,
      color: Colors.blue,
    ),
    title: Text(name),
    subtitle: Text(
      (data['role'] ?? 'member').toString(),
    ),
    trailing: const Icon(
      Icons.check_circle,
      color: Colors.green,
    ),
  );
}),
            
const SizedBox(height: 20),

// ऋण योग्य रकम शून्य भए सूचना
if (!_isLoadingEligibleAmount &&
    _eligibleLoanAmount <= 0) ...[
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.12),
      border: Border.all(color: Colors.orange),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'ऋण आवेदन सूचना',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'तपाईंको हालको ऋण योग्य रकम रु. ० छ। '
          'कृपया कोषमा उपलब्ध रकम बढेपछि केही समयपश्चात् '
          'पुनः ऋण आवेदन पेश गर्नुहोला।',
          style: TextStyle(fontSize: 14),
        ),
      ],
    ),
  ),
],

const SizedBox(height: 20),

SizedBox(
  height: 52,
  child: ElevatedButton.icon(
    icon: _isSubmitting
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.send),
    label: Text(
      _isSubmitting
          ? 'पेस हुँदैछ...'
          : 'ऋण आवेदन पेस गर्नुहोस्',
    ),
    onPressed: (_isSubmitting ||
            _isLoadingEligibleAmount ||
            _eligibleLoanAmount <= 0)
        ? null
        : () async {
            final amount = int.tryParse(
              _amountController.text.trim(),
            );

            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('सही ऋण रकम लेख्नुहोस्।'),
                ),
              );
              return;
            }

                        final selectedGuarantors = members
                            .where((doc) =>
                                _selectedGuarantorUids
                                    .contains(doc.id))
                            .map((doc) {
                          return {
                            'uid': doc.id,
                            'name': (doc.data()['name'] ?? '')
                                .toString(),
                          };
                        }).toList();

                        setState(() {
                          _isSubmitting = true;
                        });

                        try {
                          await _loanService.submitLoanApplication(
                            memberUid: widget.uid,
                            memberName: widget.memberName,
                            requestedAmount: amount,
                            purpose: _purposeController.text.trim(),
                            bsDate: toWesternDigits(_bsDateController.text.trim()),
                            adDate: _adDateController.text.trim(),
 durationMonths: _selectedDurationMonths,
       );

  if (!mounted) return;

  _amountController.clear();
                          _purposeController.clear();

 setState(() {
                            _selectedGuarantorUids.clear();
                          });

                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ऋण आवेदन सफलतापूर्वक पेस भयो।',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;

                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                'आवेदन पेस हुन सकेन: $e',
                              ),
                            ),
                          );
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isSubmitting = false;
                            });
                          }
                        }
                      },
              ),
            ),
          ],
        );
      },
    );
  }
} 
  

class MemberLoanTrackingPage extends StatelessWidget {
  final String uid;

  const MemberLoanTrackingPage({
    super.key,
    required this.uid,
  });

  String _statusText(String status) {
    switch (status) {
      case 'voting':
        return 'सदस्यहरूको मतदान भइरहेको छ';
      case 'admin_review':
        return 'Admin समीक्षा आवश्यक';
      case 'admin_pending':
        return 'Admin को अन्तिम स्वीकृति बाँकी';
      case 'active':
        return 'ऋण स्वीकृत भयो';
      case 'rejected':
        return 'ऋण आवेदन अस्वीकृत भयो';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'admin_review':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('loans')
          .where('memberUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('ऋण आवेदन विवरण लोड हुन सकेन।'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final loans = snapshot.data!.docs.toList();

        loans.sort((a, b) {
          final aDate = a.data()['submittedAt'];
          final bDate = b.data()['submittedAt'];

          final aTime = aDate is Timestamp
              ? aDate.toDate()
              : DateTime(2000);
          final bTime = bDate is Timestamp
              ? bDate.toDate()
              : DateTime(2000);

          return bTime.compareTo(aTime);
        });

        if (loans.isEmpty) {
          return const Center(
            child: Text('अहिलेसम्म कुनै ऋण आवेदन पेश गर्नुभएको छैन।'),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'मेरो ऋण आवेदन ट्र्याकिङ',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            ...loans.map((loanDoc) {
              final data = loanDoc.data();
              final status =
                  (data['status'] ?? '').toString();

              final voters =
                  (data['voters'] as List<dynamic>? ?? []);

              final submittedAt = data['submittedAt'];
              final submittedDate =
                  submittedAt is Timestamp
                      ? submittedAt.toDate()
                      : null;

              final reviewedAt = data['reviewedAt'];
              final reviewedDate =
                  reviewedAt is Timestamp
                      ? reviewedAt.toDate()
                      : null;

              return Card(
                margin: const EdgeInsets.only(bottom: 18),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.account_balance,
                            color: Colors.blue,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'ऋण आवेदन',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (status == 'active')
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                        ],
                      ),
                      const Divider(height: 24),

                      Text(
                        'माग गरिएको रकम: रु. ${data['requestedAmount'] ?? 0}',
                      ),
                      Text(
                        'प्रयोजन: ${data['purpose'] ?? '-'}',
                      ),
                      Text(
                        'अवधि: ${data['durationMonths'] ?? 0} महिना',
                      ),
                      Text(
                        'आवेदन मिति: ${toNepaliDigits(data['bsDate'] ?? '-')}',
                      ),

                      if (submittedDate != null)
                        Text(
                          'पेस भएको समय: ${submittedDate.day}/${submittedDate.month}/${submittedDate.year}',
                        ),

                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _statusColor(status),
                          ),
                        ),
                        child: Text(
                          _statusText(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Text(
                        'सदस्यहरूको मतदान विवरण',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),

                      ...voters.map((voter) {
                        final voteData =
                            Map<String, dynamic>.from(voter as Map);

                        final vote =
                            (voteData['vote'] ?? 'pending').toString();

                        final voteText = vote == 'agree'
                            ? 'सहमत'
                            : vote == 'disagree'
                                ? 'असहमत'
                                : 'मतदान बाँकी';

                        final voteColor = vote == 'agree'
                            ? Colors.green
                            : vote == 'disagree'
                                ? Colors.red
                                : Colors.orange;

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            vote == 'agree'
                                ? Icons.check_circle
                                : vote == 'disagree'
                                    ? Icons.cancel
                                    : Icons.hourglass_empty,
                            color: voteColor,
                          ),
                          title: Text(
                            (voteData['name'] ?? 'सदस्य').toString(),
                          ),
                          trailing: Text(
                            voteText,
                            style: TextStyle(
                              color: voteColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }),

                      if (status == 'active') ...[
                        const Divider(),
                        const Text(
                          'स्वीकृत ऋण विवरण',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'स्वीकृत रकम: रु. ${data['approvedAmount'] ?? 0}',
                        ),
                        Text(
                          'स्वीकृत अवधि: ${data['approvedDurationMonths'] ?? 0} महिना',
                        ),
                        if (reviewedDate != null)
                          Text(
                            'स्वीकृति मिति: ${reviewedDate.day}/${reviewedDate.month}/${reviewedDate.year}',
                          ),
                      ],

                      if (status == 'rejected')
                        const Text(
                          'तपाईंको ऋण आवेदन स्वीकृत भएन।',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}


class LoanInstallmentSubmitPage extends StatefulWidget {
  final String loanId;
  final String uid;

  const LoanInstallmentSubmitPage({
    super.key,
    required this.loanId,
    required this.uid,
  });

  @override
  State<LoanInstallmentSubmitPage> createState() =>
      _LoanInstallmentSubmitPageState();
}

class _LoanInstallmentSubmitPageState
    extends State<LoanInstallmentSubmitPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();

  XFile? _receipt;
  Uint8List? _receiptBytes;
  bool _isSubmitting = false;

  Future<void> _pickReceipt(ImageSource source) async {
  final picker = ImagePicker();

  final image = await picker.pickImage(
    source: source,
    imageQuality: 80,
  );

  if (image != null) {
    final bytes = await image.readAsBytes();

    if (!mounted) return;

    setState(() {
      _receipt = image;
      _receiptBytes = bytes;
    });
  }
}

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('कृपया भुक्तानीको रसिद फोटो छान्नुहोस्।'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await LoanService().submitLoanInstallment(
        loanId: widget.loanId,
        memberUid: widget.uid,
        amount: int.parse(_amountController.text.trim()),
        paymentBsDate: _dateController.text.trim(),
        receiptImageBytes: _receiptBytes!,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('किस्ता भुक्तानी सफलतापूर्वक पेस भयो।'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('भुक्तानी पेस हुन सकेन: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    super.dispose();
  }
    
@override
void initState() {
  super.initState();

  final today = NepaliDateTime.now();

  _dateController.text =
      '${today.year}/${today.month.toString().padLeft(2, '0')}/${today.day.toString().padLeft(2, '0')}';
}
 
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ऋण किस्ता भुक्तानी',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'किस्ता भुक्तानी रकम',
                prefixText: 'रु. ',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final amount = int.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'सही रकम राख्नुहोस्।';
                }
                return null;
              },
            ),

            const SizedBox(height: 18),

            TextFormField(
              controller: _dateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'भुक्तानी मिति (वि.सं.)',
                hintText: '२०८३/०७/१८',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'भुक्तानी मिति राख्नुहोस्।';
                }
                return null;
              },
            ),

            const SizedBox(height: 22),

            const Text(
              'भुक्तानी रसिद फोटो',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 12),

            if (_receipt != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
  _receiptBytes!,
  height: 200,
  fit: BoxFit.contain,
),
              ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () => _pickReceipt(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery बाट फोटो छान्नुहोस्'),
            ),

            OutlinedButton.icon(
              onPressed: () => _pickReceipt(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('फोटो खिच्नुहोस्'),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: const Icon(Icons.send),
              label: Text(
                _isSubmitting
                    ? 'पेस हुँदैछ...'
                    : 'किस्ता भुक्तानी पेस गर्नुहोस्',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class ApprovedLoanDetailsPage extends StatelessWidget {
  final String uid;

  const ApprovedLoanDetailsPage({
    super.key,
    required this.uid,
  });

  String _dateText(dynamic value) {
  if (value is! Timestamp) {
    return 'उपलब्ध छैन';
  }

  final date = value.toDate();
  final bs = NepaliDateTime.fromDateTime(date);

  const bsMonths = [
    'बैशाख', 'जेठ', 'असार', 'साउन',
    'भदौ', 'असोज', 'कार्तिक', 'मंसिर',
    'पुष', 'माघ', 'फागुन', 'चैत',
  ];

  const weekdays = [
    'आइतबार', 'सोमबार', 'मंगलबार', 'बुधबार',
    'बिहिबार', 'शुक्रबार', 'शनिबार',
  ];

  return toNepaliDigits('${bs.year}/${bs.month.toString().padLeft(2, '0')}/${bs.day.toString().padLeft(2, '0')} '
      '(${bsMonths[bs.month - 1]} ${bs.day} गते, ${weekdays[bs.weekday - 1]})');
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('loans')
          .where('memberUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('ऋण विवरण लोड गर्न समस्या भयो।'),
          );
        }

        final loans = (snapshot.data?.docs ?? [])
            .where((doc) => doc.data()['status'] == 'active')
            .toList();

        if (loans.isEmpty) {
          return const Center(
            child: Text('हाल कुनै स्वीकृत सक्रिय ऋण छैन।'),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: loans.map((doc) {
            final data = doc.data();

            final amount =
                data['disbursedAmount'] ?? data['approvedAmount'] ?? 0;

            final outstanding =
                data['outstandingPrincipal'] ?? amount;

            final duration =
                data['approvedDurationMonths'] ??
                data['durationMonths'] ??
                0;
 
              final durationMonths = (duration as num).toInt();

final startValue =
    data['disbursedAt'] ?? data['loanStartAt'];

NepaliDateTime? bsStartDate;

if (startValue is Timestamp) {
  bsStartDate =
      NepaliDateTime.fromDateTime(startValue.toDate());
}

NepaliDateTime? expiryDate;

if (bsStartDate != null && durationMonths > 0) {
  final monthIndex =
      bsStartDate.month - 1 + durationMonths;

  final targetYear =
      bsStartDate.year + monthIndex ~/ 12;

  final targetMonth =
      monthIndex % 12 + 1;

  final lastDay =
      NepaliDateTime(targetYear, targetMonth).totalDays;

  final targetDay =
      bsStartDate.day > lastDay
          ? lastDay
          : bsStartDate.day;

  expiryDate = NepaliDateTime(
    targetYear,
    targetMonth,
    targetDay,
  ).subtract(const Duration(days: 1));
}

final today = NepaliDateTime.now();

final bsToday = NepaliDateTime(
  today.year,
  today.month,
  today.day,
);

final remainingDays = expiryDate == null
    ? null
    : expiryDate.difference(bsToday).inDays;
              // दैनिक अद्यावधिक हुने जम्मा ऋण ब्याज
final lastInterestValue =
    data['lastInterestDate'] ?? startValue;

final interestResult =
    startValue is Timestamp && expiryDate != null
        ? LoanService().calculateLoanInterest(
            principal: (outstanding as num).toDouble(),
            lastInterestDate:
                lastInterestValue is Timestamp
                    ? lastInterestValue.toDate()
                    : startValue.toDate(),
            expiryDate: expiryDate.toDateTime(),
            calculationDate: DateTime.now(),
            baseMonthlyRate: (data['monthlyInterestRate'] as num?)?.toDouble(),
            originalLoanAmount: (data['approvedAmount'] ?? data['requestedAmount'] ?? outstanding) as num,
            useAmountBasedRules: data['monthlyInterestRate'] != null,
          )
        : {
            'interest': 0.0,
            'overdueDays': 0,
            'actionRequired': false,
          };

final totalInterest =
    (interestResult['interest'] as num).toDouble();

            return Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 14,
  ),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [
        Color(0xFF08254A),
        Color(0xFF174B78),
      ],
    ),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: const Color(0xFFE8B943),
      width: 1.5,
    ),
  ),
  child: const Text(
    'स्वीकृत ऋण विवरण',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w900,
      color: Color(0xFFFFD76A),
      letterSpacing: 0.5,
    ),
  ),
),
                    const Divider(height: 24),
                    _loanDetailRow('जम्मा ऋण', 'रु. $amount'),
                    _loanDetailRow(
                      'ऋण लिएको मिति',
                      _dateText(data['disbursedAt'] ?? data['loanStartAt']),
                    ),
                    _loanDetailRow(
                      'ऋणको प्रयोजन',
                      data['purpose']?.toString() ?? 'उपलब्ध छैन',
                    ),
 
_loanDetailRow('स्वीकृत अवधि', '$duration महिना'),

_loanDetailRow(
  'अवधि समाप्त हुने मिति',
  expiryDate == null
      ? 'उपलब्ध छैन'
      : _dateText(Timestamp.fromDate(expiryDate)),
),

_loanDetailRow(
  'बाँकी अवधि',
  remainingDays == null
      ? 'उपलब्ध छैन'
      : remainingDays < 0
          ? 'अवधि समाप्त'
          : '$remainingDays दिन',
),

_loanDetailRow(
  'बाँकी साँवा',
  'रु. $outstanding',
),
  _loanDetailRow(
  'जम्मा ब्याज',
   'रु. ${totalInterest.toStringAsFixed(2)}',
),

const SizedBox(height: 22),

Container(
  width: double.infinity,
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [
        Color(0xFF063B78),
        Color(0xFF0878C9),
        Color(0xFF00A6C7),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: const Color(0xFFFFD166),
      width: 2,
    ),
    boxShadow: const [
      BoxShadow(
        color: Colors.black26,
        blurRadius: 9,
        offset: Offset(0, 4),
      ),
    ],
  ),
  child: ElevatedButton.icon(
    icon: const Icon(
      Icons.account_balance_wallet,
      color: Colors.white,
      size: 26,
    ),
    label: const Text(
      'किस्ता भुक्तानी पेश गर्नुहोस्',
      style: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      minimumSize: const Size(double.infinity, 58),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('किस्ता भुक्तानी पेश गर्नुहोस्'),
            ),
            body: LoanInstallmentSubmitPage(
              loanId: doc.id,
              uid: uid,
            ),
          ),
        ),
      );
    },
  ),
),

],

                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _loanDetailRow(String label, String value) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFFEAF3FF),
          Color(0xFFF5F8FF),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: const Color(0xFFB8D0EE),
        width: 1,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF183B63),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF092B50),
            ),
          ),
        ),
      ],
    ),
  );
}
}

class LoanMenuPage extends StatelessWidget {
  final String memberName;
  final String uid;

  const LoanMenuPage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Text(
            'ऋण सेवा',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'स्वागत छ, $memberName',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const Icon(
                Icons.file_present,
                size: 38,
                color: Colors.blue,
              ),
              title: const Text(
                'ऋण आवेदन',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'नयाँ ऋण आवेदन तथा आवेदनको स्थिति',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                    appBar: AppBar(
                    title: const Text('ऋण आवेदन'),
                     ),
                    body: LoanApplicationPage(
                     memberName: memberName,
                       uid: uid,
                    ),
                   ),
                  ),
                );
              },
            ),
          ),

                    const SizedBox(height: 16),

          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const Icon(
                Icons.track_changes,
                size: 38,
                color: Colors.orange,
              ),
              title: const Text(
                'आवेदन ट्र्याकिङ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'मतदान, प्रशासनिक निर्णय र आवेदनको अवस्था हेर्नुहोस्',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: const Text('ऋण आवेदन ट्र्याकिङ'),
                      ),
                      body: MemberLoanTrackingPage(uid: uid),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const Icon(
                Icons.account_balance_wallet,
                size: 38,
                color: Colors.green,
              ),
              title: const Text(
                'ऋण विवरण',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'स्वीकृत ऋण, बाँकी साँवा, ब्याज र भुक्तानी इतिहास',
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              
                onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: const Text('स्वीकृत ऋणको विवरण'),
        ),
                body: ApprovedLoanDetailsPage(uid: uid),
      ),
    ),
  );
},
          ),
        ),
      ],
    ),
  ),
);
  }
}

class MonthlySavingsEntryPage extends StatefulWidget {
  const MonthlySavingsEntryPage({super.key});

  @override
  State<MonthlySavingsEntryPage> createState() =>
      _MonthlySavingsEntryPageState();
}

class _MonthlySavingsEntryPageState
    extends State<MonthlySavingsEntryPage> {
  final MonthlySavingsService _service = MonthlySavingsService();
  final TextEditingController _monthController =
      TextEditingController();
  final TextEditingController _savingsController =
      TextEditingController(text: '2000');
  final TextEditingController _insuranceController =
      TextEditingController(text: '300');

  String? _selectedUid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _monthController.text = '2083-08';
  }

  @override
  void dispose() {
    _monthController.dispose();
    _savingsController.dispose();
    _insuranceController.dispose();
    super.dispose();
  }

  Future<void> _saveRecord() async {
    final uid = _selectedUid;
    final month = _monthController.text.trim();
    final savings = int.tryParse(_savingsController.text.trim());
    final insurance = int.tryParse(_insuranceController.text.trim());

    if (uid == null ||
        month.isEmpty ||
        savings == null ||
        insurance == null ||
        savings < 0 ||
        insurance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('सदस्य, महिना र सही रकम भर्नुहोस्।'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _service.saveMonthlyRecord(
        memberUid: uid,
        monthKey: month,
        savingsAmount: savings,
        insuranceAmount: insurance,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('मासिक रेकर्ड सुरक्षित भयो।'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
        debugPrint('ERROR TYPE: ${e.runtimeType}');
debugPrint('ERROR VALUE: $e');

try {
  final dynamic err = e;
  debugPrint('BOXED ERROR: ${err.error}');
  debugPrint('BOXED STACK: ${err.stack}');
} catch (debugError) {
  debugPrint('ERROR DETAILS: $debugError');
}
      if (!mounted) return;

      debugPrint('मासिक बचत सुरक्षित गर्दा Error: $e');

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      'रेकर्ड सुरक्षित भएन: ${e.toString()}',
    ),
    backgroundColor: Colors.red,
    duration: const Duration(seconds: 8),
  ),
);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
    
  

Future<void> _create12Months() async {
  if (_saving) return;

  setState(() => _saving = true);

  try {
    final db = FirebaseFirestore.instance;

    final membersSnapshot = await db.collection('member').get();

    if (membersSnapshot.docs.length != 6) {
      throw StateError(
        'Firebase मा ठीक ६ जना सदस्य हुनुपर्छ। '
        'अहिले भेटिएका सदस्य: ${membersSnapshot.docs.length}',
      );
    }

    final batch = db.batch();
    int newRecords = 0;

    for (final memberDoc in membersSnapshot.docs) {
      int year = 2083;
      int month = 7;

      for (int i = 0; i < 12; i++) {
        final monthKey =
            '$year-${month.toString().padLeft(2, '0')}';

        final ref = db
            .collection('monthly_savings')
            .doc('${memberDoc.id}_$monthKey');

        final existing = await ref.get();

        // पहिल्यै भएको रेकर्डलाई नछुने।
        if (!existing.exists) {
          batch.set(ref, {
            'memberUid': memberDoc.id,
            'monthKey': monthKey,
            'savingsAmount': 2000,
            'insuranceAmount': 300,
            'totalDue': 2300,
           'paidAmount': 0,
'insurancePaid': 0,
'savingsPaid': 0,
'status': 'pending',
'createdAt': FieldValue.serverTimestamp(),
          });

          newRecords++;
        }

        month++;
        if (month > 12) {
          month = 1;
          year++;
        }
      }
    }

    if (newRecords > 0) {
      await batch.commit();
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newRecords == 0
              ? 'पहिल्यै भएका रेकर्ड सुरक्षित छन्। नयाँ रेकर्ड आवश्यक परेन।'
              : '$newRecords नयाँ रेकर्ड थपिए। पुराना रेकर्ड सुरक्षित रहे।',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('रेकर्ड जाँच्न सकिएन: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ),
    );
  } finally {
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}

        
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मासिक बचत प्रविष्टि'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('member')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('सदस्य विवरण लोड भएन।'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final members = snapshot.data!.docs;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: _selectedUid,
                decoration: const InputDecoration(
                  labelText: 'सदस्य छान्नुहोस्',
                  border: OutlineInputBorder(),
                ),
                items: members.map((doc) {
                  final data = doc.data();
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(
                      (data['name'] ?? 'नाम छैन').toString(),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedUid = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _monthController,
                decoration: const InputDecoration(
                  labelText: 'महिना (BS)',
                  hintText: '2083-07',
                  helperText: 'उदाहरण: 2083-07',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _savingsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'मासिक बचत (रु.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _insuranceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'बीमा रकम (रु.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _saveRecord,
                icon: const Icon(Icons.save),
                label: Text(
                  _saving ? 'सुरक्षित हुँदैछ...' : 'Firebase मा सुरक्षित गर्नुहोस्',
                ),
              ),
                const SizedBox(height: 12),
OutlinedButton.icon(
  onPressed: _saving ? null : _create12Months,
  icon: const Icon(Icons.calendar_month),
  label: Text(
    _saving
        ? 'रेकर्ड बनाउँदैछ...'
        : 'आगामी १२ महिनाका रेकर्ड बनाउनुहोस्',
  ),
),
            ],
          );
        },
      ),
    );
  }
}

  
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  static const Color navy = Color(0xFF101B3A);
  static const Color gold = Color(0xFFE8C56A);
  static const Color teal = Color(0xFF1B8A83);

  void _openInsuranceManagement(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminInsuranceManagementPage(),
      ),
    );
  }
    
  Future<void> _openPaymentEntry(BuildContext context) async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('member').get();

      if (!context.mounted) return;

      // Admin पनि नियमित सदस्य भएकाले सदस्य छनोट सूचीमा समावेश हुन्छन्।
      final members = snapshot.docs.toList()
        ..sort((a, b) => (a.data()['name'] ?? '')
            .toString()
            .compareTo((b.data()['name'] ?? '').toString()));

      if (members.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('सदस्यको विवरण भेटिएन।')),
        );
        return;
      }

      final selected = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('भुक्तानी गर्ने सदस्य छान्नुहोस्'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: members.map((doc) {
                final name = doc.data()['name']?.toString() ?? 'नाम छैन';
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(name),
                  onTap: () => Navigator.pop(dialogContext, doc),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('रद्द गर्नुहोस्'),
            ),
          ],
        ),
      );

      if (!context.mounted || selected == null) return;

      final name = selected.data()['name']?.toString() ?? 'नाम छैन';

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentFormPage(
            memberName: name,
            uid: selected.id,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('सदस्यको सूची खोल्न असफल: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ('भुक्तानी प्रविष्टि गर्नुहोस्', Icons.add_card, teal),
      ('भुक्तानी स्वीकृति', Icons.fact_check_outlined, teal),
      ('सदस्य व्यवस्थापन', Icons.groups_outlined, navy),
      ('मासिक बचत', Icons.savings_outlined, gold),
      ('बीमा व्यवस्थापन', Icons.health_and_safety_outlined, teal),
      ('ऋण व्यवस्थापन', Icons.account_balance_outlined, navy),
      ('रिपोर्ट तथा हिसाब', Icons.assessment_outlined, gold),
        ('जरिमाना व्यवस्थापन', Icons.money_off_csred_outlined, Colors.red),
  ('भुक्तानी ढिलाइ सूचना', Icons.event_note, Colors.orange),
  ('जन्मदिन तथा श्रद्धाञ्जली', Icons.cake_outlined, Colors.purple),
 ('खर्च प्रस्ताव तथा स्वीकृति', Icons.receipt_long, Colors.deepOrange),       
    ];

    return Scaffold(
              appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: navy,
        foregroundColor: gold,
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where(
                  'memberUid',
                  isEqualTo:
                      FirebaseAuth.instance.currentUser?.uid ?? '',
                )
                .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = (snapshot.data?.docs ?? [])
                  .where((doc) => doc.data()['isRead'] != true)
                  .length;

              return Stack(
                children: [
                  IconButton(
                    tooltip: 'सूचनाहरू',
                    icon: const Icon(Icons.notifications, size: 27),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationPage(
                            memberUid:
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 5,
                      top: 5,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: Colors.red,
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F5F9),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [navy, Color(0xFF253C68)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings, color: gold, size: 38),
                  SizedBox(height: 12),
                  Text(
                    'पारिवारिक बचत कोष',
                    style: TextStyle(
                      color: gold,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'व्यवस्थापन मेनु',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.12,
              ),
              itemBuilder: (context, index) {
                final item = items[index];

                return Card(
                  elevation: 2,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
   
onTap: () {
  if (index == 0) {
    _openPaymentEntry(context);
  } else if (index == 1) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PaymentApprovalPage(),
      ),
    );
  } else if (index == 2) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMemberManagementPage()));
  } else if (index == 3) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MonthlySavingsEntryPage(),
      ),
    );
   } else if (index == 4) {
    _openInsuranceManagement(context);
  } else if (index == 5) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoanAdminMenuPage(),
      ),
    );
  } else if (index == 6) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminFinancialReportsMenuPage(),
      ),
    );
  } else if (index == 10) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ExpenseWithdrawalAdminPage(),
      ),
    );

  } else if (index == 7) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PenaltyManagementPage(),
      ),
    );
  } else if (index == 8) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminLatePaymentNoticePage(
          adminUid: FirebaseAuth.instance.currentUser!.uid,
        ),
      ),
    );
  } else if (index == 9) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAnniversaryManagementPage(),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${item.$1} — अर्को चरणमा जोडिनेछ।',
        ),
      ),
    );
  }
},
child: Padding(
                 padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.$2, color: item.$3, size: 34),
                          const SizedBox(height: 12),
                          Text(
                            item.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: navy,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


class AdminFinancialReportsMenuPage extends StatelessWidget {
  const AdminFinancialReportsMenuPage({super.key});

  static const Color navy = Color(0xFF101B3A);
  static const Color gold = Color(0xFFE8C56A);

  final List<Map<String, dynamic>> reportMenus = const [
    {
      'title': 'आर्थिक प्रतिवेदन',
      'icon': Icons.assessment_outlined,
    },
    {
      'title': 'आर्थिक हिसाब',
      'icon': Icons.account_balance_wallet_outlined,
    },
    {
      'title': 'मासिक प्रतिवेदन',
      'icon': Icons.calendar_month,
    },
    {
      'title': 'वार्षिक प्रतिवेदन',
      'icon': Icons.date_range,
    },
    {
      'title': 'सदस्यगत प्रतिवेदन',
      'icon': Icons.people_outline,
    },
    {
      'title': 'सदस्य प्रतिवेदन इतिहास',
      'icon': Icons.history,
    },
    {
      'title': 'Admin Audit History',
      'icon': Icons.admin_panel_settings_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('रिपोर्ट तथा हिसाब'),
        backgroundColor: navy,
        foregroundColor: gold,
      ),
      backgroundColor: const Color(0xFFF4F5F9),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reportMenus.length,
        itemBuilder: (context, index) {
          final item = reportMenus[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(item['icon'] as IconData, color: navy),
              title: Text(
                item['title'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
onTap: () {
  if (index == 0) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinancialReportPage(
          memberUid:
              FirebaseAuth.instance.currentUser!.uid,
          memberName: 'प्रशासक',
          role: 'admin',
        ),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
        'यो सुविधा अर्को चरणमा जोडिनेछ।',
        ),
      ),
    );
  }
},
            ),
          );
        },
      ),
    );
  }
}


Future<void> _showExpenseProposalDialog(BuildContext context) async {
  final titleController = TextEditingController();
  final categoryController = TextEditingController();
  final amountController = TextEditingController();
  final descriptionController = TextEditingController();

  NepaliDateTime? selectedExpenseDate;
bool isSubmitting = false;

String? voucherUrl;
String? voucherFileName;
bool isUploadingVoucher = false;
  await showDialog(
    context: context,
    builder: (dialogContext) {
  return StatefulBuilder(
    builder: (context, setDialogState) {
      final canSubmit =
          titleController.text.trim().isNotEmpty &&
          (int.tryParse(amountController.text.trim()) ?? 0) > 0 &&
          selectedExpenseDate != null &&
          descriptionController.text.trim().isNotEmpty &&
          voucherUrl != null &&
          voucherUrl!.isNotEmpty &&
          !isUploadingVoucher &&
          !isSubmitting;

            return AlertDialog(
        title: const Text('नयाँ खर्च प्रस्ताव'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
  value: titleController.text.isEmpty
      ? null
      : titleController.text,
  decoration: const InputDecoration(
    labelText: 'खर्चको शीर्षक छान्नुहोस्',
  ),
  items: const [
    DropdownMenuItem(
      value: 'संस्थागत खर्च',
      child: Text('संस्थागत खर्च'),
    ),
    DropdownMenuItem(
      value: 'पारिवारिक खर्च',
      child: Text('पारिवारिक खर्च'),
    ),
    DropdownMenuItem(
      value: 'सहयोग वा दान',
      child: Text('सहयोग वा दान'),
    ),
    DropdownMenuItem(
      value: 'अन्य खर्च',
      child: Text('अन्य खर्च'),
    ),
  ],
  onChanged: (value) {
    setDialogState(() {
      titleController.text = value ?? '';
      categoryController.text = value ?? '';
    });
  },
),
                  
   TextField(
   controller: amountController,
       onChanged: (_) {
  setDialogState(() {});
},
   keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'खर्च रकम (रु.)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      selectedExpenseDate == null
                          ? 'खर्च भएको BS मिति छान्नुहोस्'
                          : toNepaliDigits('${selectedExpenseDate!.year}-'
                            '${selectedExpenseDate!.month.toString().padLeft(2, '0')}-'
                            '${selectedExpenseDate!.day.toString().padLeft(2, '0')}'),
                    ),
                    onPressed: () async {
                      final pickedDate =
                          await showNepaliDatePicker(
                        context: context,
                        initialDate:
                            selectedExpenseDate ??
                                NepaliDateTime.now(),
                        firstDate: NepaliDateTime(2070, 1, 1),
                        lastDate: NepaliDateTime.now(),
                      );

                      if (pickedDate != null) {
                        setDialogState(() {
                          selectedExpenseDate = pickedDate;
                        });
                      }
                    },
                  ),
                  TextField(
                    controller: descriptionController,
                      onChanged: (_) {
  setDialogState(() {});
},
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'खर्चको विवरण',
                    ),
                  ),
                    const SizedBox(height: 16),

OutlinedButton.icon(
  icon: const Icon(Icons.upload_file),
  label: Text(
    voucherFileName ?? 'Voucher फोटो वा PDF छान्नुहोस्',
  ),
  onPressed: isUploadingVoucher
      ? null
      : () async {
          final choice = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Voucher को प्रकार छान्नुहोस्'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('फोटो'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('PDF'),
                ),
              ],
            ),
          );

          if (choice == null) return;

          setDialogState(() {
            isUploadingVoucher = true;
          });

          try {
            final result =
                await ExpenseWithdrawalService().uploadVoucher(
              proposalId: 'pending_${DateTime.now().millisecondsSinceEpoch}',
              isPdf: choice,
            );

            if (result == null || result['url'] == null) {
  throw Exception('Voucher Upload हुन सकेन।');
}

setDialogState(() {
  voucherUrl = result['url'];
  voucherFileName = result['fileName'];
  isUploadingVoucher = false;
});
          } catch (e) {
            setDialogState(() {
              isUploadingVoucher = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Voucher Upload भएन: $e')),
            );
          }
        },
),

if (voucherUrl != null &&
    !voucherFileName!.toLowerCase().endsWith('.pdf'))
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Image.network(
      voucherUrl!,
      height: 160,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Text('फोटो Preview देखाउन सकिएन।');
      },
    ),
  )
else if (voucherUrl != null)
  ListTile(
    leading: const Icon(Icons.picture_as_pdf),
    title: Text(voucherFileName ?? 'PDF Voucher'),
  ),
                    
if (isUploadingVoucher)
  const Padding(
    padding: EdgeInsets.all(8),
    child: CircularProgressIndicator(),
  ),
                ],
              ),
            ),
            actions: [
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
              TextButton(
  style: TextButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.red,
    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  ),
  onPressed: isSubmitting
      ? null
      : () => Navigator.pop(dialogContext),
  child: const Text('रद्द गर्नुहोस्'),
),
              ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.yellow,
    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  ),
  onPressed: !canSubmit
    ? null
    : () async {
    if (isUploadingVoucher) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voucher Upload पूरा भएपछि मात्र प्रस्ताव पेस गर्न मिल्छ।',
          ),
        ),
      );
      return;
    }

    final title =
        titleController.text.trim();
       
  final category = title;
  final amount = int.tryParse(
                          amountController.text.trim(),
                        );

                        if (title.isEmpty ||
                            category.isEmpty ||
                            amount == null ||
                            amount <= 0 ||
                            selectedExpenseDate == null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'सबै आवश्यक विवरण भर्नुहोस् र BS मिति छान्नुहोस्।',
                              ),
                            ),
                          );
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                        });

                        try {
      final availableAmount =
    await FundService().calculateAvailableSavings();

final maxExpenseAmount = availableAmount * 0.20;

if (amount > maxExpenseAmount) {
  setDialogState(() {
    isSubmitting = false;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'उपलब्ध रकमको २०% भन्दा बढी खर्च प्रस्ताव राख्न मिल्दैन। '
        'अधिकतम प्रस्ताव रकम रु. ${maxExpenseAmount.toStringAsFixed(2)} हो।',
      ),
    ),
  );

  return;
}
     final bsDate =
                              '${selectedExpenseDate!.year}-'
                              '${selectedExpenseDate!.month.toString().padLeft(2, '0')}-'
                              '${selectedExpenseDate!.day.toString().padLeft(2, '0')}';

                          final adDate =
                              selectedExpenseDate!.toDateTime();

                          await ExpenseWithdrawalService()
                              .submitProposal(
                            title: title,
                            category: category,
                            amount: amount.toDouble(),
                            bsDate: bsDate,
                            expenseDate: adDate,
 description:                                    descriptionController.text.trim(),
 voucherUrl: voucherUrl!,
 voucherFileName: voucherFileName!,
                          );

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'खर्च प्रस्ताव सफलतापूर्वक पेस भयो।',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                          });

                          showDialog<void>(
  context: dialogContext,
  builder: (alertContext) => AlertDialog(
    title: const Text('प्रस्ताव पेस हुन सकेन'),
    content: Text('$e'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(alertContext),
        child: const Text('ठीक छ'),
      ),
    ],
  ),
);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('प्रस्ताव पेस गर्नुहोस्'),
                  ),  
                ],
              ),
            ],
          );
        },
      );
    },
  );

  titleController.dispose();
  categoryController.dispose();
  amountController.dispose();
  descriptionController.dispose();
}

class ExpenseWithdrawalAdminPage extends StatefulWidget {
  const ExpenseWithdrawalAdminPage({super.key});

  @override
  State<ExpenseWithdrawalAdminPage> createState() =>
      _ExpenseWithdrawalAdminPageState();
}

class _ExpenseWithdrawalAdminPageState
    extends State<ExpenseWithdrawalAdminPage> {
   
    String _memberPhoto(String? name) {
  switch (name?.trim()) {
    case 'कमला देउजा':
      return 'assets/member1.jpg';
    case 'हरि कुमार चौहान':
      return 'assets/member2.jpg';
    case 'बाल कुमार चौहान':
      return 'assets/member3.jpg';
    case 'चन्द्र बहादुर चौहान':
      return 'assets/member4.jpg';
    case 'टिकाराम चौहान':
      return 'assets/member5.jpg';
    case 'उदय चौहान':
      return 'assets/member6.jpg';
    default:
      return 'assets/official_logo.png';
  }
}
   
void _showVoteDetails({
  required BuildContext context,
  required String memberName,
  required String voteStatus,
  dynamic votedAt,
}) {
  final isPending = voteStatus == 'pending';

  final voteText = isPending
      ? 'मतदान गर्न बाँकी'
      : voteStatus == 'yes'
          ? 'स्वीकृत मत'
          : 'अस्वीकृत मत';

  final voteColor = isPending
      ? Colors.orange
      : voteStatus == 'yes'
          ? Colors.green
          : Colors.red;

  final voteTime = votedAt is Timestamp
      ? votedAt.toDate().toString()
      : 'उपलब्ध छैन';

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('सदस्यको मतदान विवरण'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundImage: AssetImage(_memberPhoto(memberName)),
          ),
          const SizedBox(height: 12),
          Text(
            memberName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            voteText,
            style: TextStyle(
              color: voteColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text('मतदान समय: $voteTime'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('बन्द गर्नुहोस्'),
        ),
      ],
    ),
  );
}
    
      Future<void> _uploadExpenseVoucher(
    BuildContext context,
    String proposalId,
    bool isPdf,
  ) async {
    try {
      final result =
          await ExpenseWithdrawalService().uploadVoucher(
        proposalId: proposalId,
        isPdf: isPdf,
      );

      if (result == null) return;

      await ExpenseWithdrawalService().attachVoucherToProposal(
        proposalId: proposalId,
        voucherUrl: result['url']!,
        fileName: result['fileName']!,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('भुक्तानी Voucher सफलतापूर्वक अपलोड भयो।'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voucher अपलोड हुन सकेन: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
    
  @override
  Widget build(BuildContext context) {
    return Scaffold(
  appBar: AppBar(
    backgroundColor: const Color(0xFF101B3A),
    foregroundColor: const Color(0xFFE8C56A),
    title: const Text('खर्च प्रस्ताव तथा स्वीकृति'),
    actions: [
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'नयाँ खर्च प्रस्ताव',
        onPressed: () {
          _showExpenseProposalDialog(context);
        },
      ),
    ],
  ),
  body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('expense_withdrawal_proposals')
            .orderBy('submittedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('खर्च प्रस्ताव लोड गर्न समस्या भयो।'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final proposals = snapshot.data?.docs ?? [];

          if (proposals.isEmpty) {
            return const Center(
              child: Text('अहिलेसम्म कुनै खर्च प्रस्ताव छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: proposals.length,
            itemBuilder: (context, index) {
              final data = proposals[index].data();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: proposals[index].reference
      .collection('votes')
      .snapshots(),
  builder: (context, voteSnapshot) {
    final eligibleCount =
        (data['eligibleVoterCount'] as num? ?? 0).toInt();

    final votes = voteSnapshot.data?.docs ?? [];
    final yesVotes = votes.where(
      (v) => v.data()['vote'] == 'yes',
    ).length;
    final noVotes = votes.where(
      (v) => v.data()['vote'] == 'no',
    ).length;

    final deadline = data['votingDeadline'] is Timestamp
        ? (data['votingDeadline'] as Timestamp).toDate()
        : null;

    final allVoted =
        eligibleCount > 0 && votes.length >= eligibleCount;

    final deadlinePassed = deadline != null &&
        !DateTime.now().isBefore(deadline);

    final canCount = allVoted || deadlinePassed;

    return Card(
  color: const Color(0xFF1E3A5F),
  elevation: 3,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: const BorderSide(
      color: Color(0xFFFFCC80),
      width: 1,
    ),
  ),
  margin: const EdgeInsets.only(bottom: 12),
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              (data['title'] ?? 'खर्च प्रस्ताव').toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text('रकम: रु. ${data['amount'] ?? 0}'),
            Text(
  'स्थिति: ${{
    'voting': 'मतदान जारी',
    'approved': 'खर्च स्वीकृत',
    'disbursed': 'रकम निकासी भयो',
    'rejected': 'खर्च अस्वीकृत',
  }[data['status']] ?? 'अज्ञात'}',
  style: TextStyle(
    color: data['status'] == 'voting'
        ? Colors.orange
        : data['status'] == 'approved'
            ? Colors.yellow
            : data['status'] == 'disbursed'
                ? Colors.green
                : data['status'] == 'rejected'
                    ? Colors.red
                    : Colors.white,
    fontWeight: FontWeight.bold,
  ),
),
            Text('कुल योग्य सदस्य: $eligibleCount'),
            Text('मतदान: ${votes.length}/$eligibleCount'),
            Text('स्वीकृति मत: $yesVotes'),
            Text('अस्वीकृति मत: $noVotes'),
              const SizedBox(height: 10),
const Text(
  'सदस्यहरूको मतदान:',
  style: TextStyle(fontWeight: FontWeight.bold),
),
const SizedBox(height: 10),

Builder(
  builder: (context) {
    final eligibleUids =
        List<String>.from(data['eligibleVoterUids'] ?? []);

    final voteByUid = {
      for (final vote in votes) vote.id: vote.data(),
    };

    return FutureBuilder<
        List<DocumentSnapshot<Map<String, dynamic>>>>(
      future: Future.wait(
        eligibleUids.map(
          (uid) => FirebaseFirestore.instance
              .collection('member')
              .doc(uid)
              .get(),
        ),
      ),
      builder: (context, memberSnapshot) {
        if (!memberSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final members = memberSnapshot.data!;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: members.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) {
            final memberDoc = members[index];
            final memberData = memberDoc.data() ?? {};

            final memberName =
                (memberData['name'] ?? 'नाम उपलब्ध छैन')
                    .toString();

            final voteData = voteByUid[memberDoc.id];
            final voteType =
                (voteData?['vote'] ?? 'pending').toString();

            final voteText = voteType == 'yes'
                ? 'स्वीकृत'
                : voteType == 'no'
                    ? 'अस्वीकृत'
                    : 'बाँकी';

            final voteColor = voteType == 'yes'
                ? Colors.green
                : voteType == 'no'
                    ? Colors.red
                    : Colors.orange;

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _showVoteDetails(
                  context: context,
                  memberName: memberName,
                  voteStatus: voteType,
                  votedAt: voteData?['votedAt'],
                );
              },
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 29,
                    backgroundImage:
                        AssetImage(_memberPhoto(memberName)),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    voteText,
                    style: TextStyle(
                      color: voteColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  },
),
            const SizedBox(height: 10),
            if (data['status'] == 'voting' &&
                data['votingStatus'] != 'admin_tiebreak_pending')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canCount
                      ? () async {
                          try {
                            await ExpenseWithdrawalService()
                                .finalizeExpiredVoting(
                              proposalId: proposals[index].id,
                            );

                            if (!context.mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('मत गणना सफल भयो।'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      : null,
                  child: const Text('मत गणना तथा निर्णय'),
                ),
              ),
              
                          if (data['status'] == 'voting' &&
                data['votingStatus'] == 'admin_tiebreak_pending')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ExpenseWithdrawalService()
                              .castAdminTieBreakVote(
                            proposalId: proposals[index].id,
                            approve: true,
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      },
                      child: const Text('स्वीकृत गर्ने'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ExpenseWithdrawalService()
                              .castAdminTieBreakVote(
                            proposalId: proposals[index].id,
                            approve: false,
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      },
                      child: const Text('अस्वीकृत गर्ने'),
                    ),
                  ),
                ],
              ),

            if (data['status'] == 'approved' ||
    data['status'] == 'disbursed')
  Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(),

      if (data['status'] == 'approved') ...[
        const Text(
          'भुक्तानी Voucher Upload',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _uploadExpenseVoucher(
            context,
            proposals[index].id,
            false,
          ),
          icon: const Icon(Icons.image),
          label: const Text('Voucher फोटो छान्नुहोस्'),
        ),
        ElevatedButton.icon(
          onPressed: () => _uploadExpenseVoucher(
            context,
            proposals[index].id,
            true,
          ),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Voucher PDF छान्नुहोस्'),
        ),
      ],
 
        // Payment Voucher Filename
if ((data['paymentVoucherFileName'] ?? '')
    .toString()
    .isNotEmpty)
  InkWell(
    onTap: () async {
  final url =
      (data['paymentVoucherUrl'] ?? '').toString();

  if (url.isEmpty) return;

  if (url.toLowerCase().endsWith('.pdf')) {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('फोटो खोल्न सकिएन।'),
              );
            },
          ),
        ),
      ),
    );
  }
},
    child: Text(
      'भुक्तानीको Voucher: ${data['paymentVoucherFileName']} (खोल्नुहोस्)',
      style: const TextStyle(
        color: Colors.green,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline,
      ),
    ),
  ),

// Payment Voucher Preview
if ((data['paymentVoucherUrl'] ?? '')
        .toString()
        .isNotEmpty &&
    !(data['paymentVoucherFileName'] ?? '')
        .toString()
        .toLowerCase()
        .endsWith('.pdf'))
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
       data['paymentVoucherUrl'].toString(),
        width: double.infinity,
        height: 180,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Text('Payment Voucher फोटो देखाउन सकिएन।');
        },
      ),
    ),
  ),


// Proposal Voucher Filename
if ((data['proposalVoucherFileName'] ??
        (data['paymentVoucherFileName'] == null
            ? data['voucherFileName']
            : null) ??
        '')
    .toString()
    .isNotEmpty)
  Text(
    'प्रस्तावको Voucher: ${data['proposalVoucherFileName'] ?? (data['paymentVoucherFileName'] == null ? data['voucherFileName'] : '')}',
    style: const TextStyle(
      color: Colors.blue,
      fontWeight: FontWeight.bold,
    ),
  ),

// Proposal Voucher Preview
if ((data['proposalVoucherUrl'] ??
        (data['paymentVoucherUrl'] == null
            ? data['voucherUrl']
            : null) ??
        '')
        .toString()
        .isNotEmpty &&
    !((data['proposalVoucherFileName'] ??
                (data['paymentVoucherFileName'] == null
                    ? data['voucherFileName']
                    : null) ??
                '')
            .toString()
            .toLowerCase()
            .endsWith('.pdf')))
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        (data['proposalVoucherUrl'] ??
                (data['paymentVoucherUrl'] == null                    ? data['voucherUrl']
                    : null))
            .toString(),
        width: double.infinity,
                height: 180,
      ),
    ),
  ),
    ],
  ),
if (data['status'] == 'approved' &&
    (data['paymentVoucherUrl'] ?? '')
        .toString()
        .trim()
        .isNotEmpty)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () async {
        try {
          await ExpenseWithdrawalService()
              .disburseApprovedProposal(
            proposalId: proposals[index].id,
          );

          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('भुक्तानी पूरा भयो। रकम कोषबाट कट्टा भयो।'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('भुक्तानी असफल भयो: $e')),
          );
        }
      },
            icon: const Icon(Icons.account_balance_wallet),
      label: const Text('Disburse / भुक्तानी पूरा गर्नुहोस्'),
    ),
  ),
       ],
      ),
     ),
    ),
  );
  },
);
            },
          );
        },
      ),
    );
  }
}

class PaymentApprovalPage extends StatelessWidget {
  const PaymentApprovalPage({super.key});

  Future<void> _approve(
    BuildContext context,
    String paymentId,
    int originalAmount,
    String adminUid,
  ) async {
    final controller = TextEditingController(
      text: originalAmount.toString(),
    );

    final approvedAmount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('भुक्तानी स्वीकृति'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('पेस गरिएको रकम: रु. $originalAmount'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'स्वीकृत रकम (रु.)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('रद्द गर्नुहोस्'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = int.tryParse(controller.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('सही रकम लेख्नुहोस्।'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, amount);
            },
            child: const Text('स्वीकृत गर्नुहोस्'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (approvedAmount == null || !context.mounted) return;

    try {
      await PaymentService().approvePayment(
        paymentId: paymentId,
        adminUid: adminUid,
        approvedAmount: approvedAmount,
        adminNote: approvedAmount == originalAmount
            ? 'मासिक भुक्तानी स्वीकृत'
            : 'रकम रु. $originalAmount बाट रु. $approvedAmount मा सच्याइयो',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('भुक्तानी सफलतापूर्वक स्वीकृत भयो।'),
          backgroundColor: Colors.green,
        ),
      );
 } catch (e, stackTrace) {
  debugPrint('APPROVE ERROR TYPE: ${e.runtimeType}');
  debugPrint('APPROVE ERROR: $e');
  debugPrint('APPROVE STACK: $stackTrace');

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'स्वीकृति असफल: ${e.runtimeType}\n$e',
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 15),
    ),
  );
}
}
  Future<void> _reject(
    BuildContext context,
    String paymentId,
    String adminUid,
  ) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('भुक्तानी अस्वीकार'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'अस्वीकार गर्नुको कारण',
            hintText: 'कारण लेख्नुहोस्',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('रद्द गर्नुहोस्'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('अस्वीकारको कारण लेख्नुहोस्।'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('अस्वीकार गर्नुहोस्'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (reason == null || !context.mounted) return;

    try {
      await PaymentService().rejectPayment(
        paymentId: paymentId,
        adminUid: adminUid,
        reason: reason,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('भुक्तानी अस्वीकार गरियो।'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('अस्वीकार गर्न सकिएन: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('भुक्तानी स्वीकृति')),
        body: const Center(
          child: Text('पहिले लगइन गर्नुहोस्।'),
        ),
      );
    }

    final adminUid = currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('भुक्तानी स्वीकृति'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PaymentService().watchPendingPayments(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'भुक्तानी लोड भएन। Firebase Rules जाँच गर्नुहोस्।',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('अहिले स्वीकृतिका लागि भुक्तानी छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final amount = (data['amount'] as num?)?.toInt() ?? 0;
              final createdAt = data['createdAt'] as Timestamp?;
              final dateText = createdAt == null
                  ? 'पेस गरिएको समय: उपलब्ध छैन'
                  : 'पेस गरिएको: ${createdAt.toDate().toLocal()}';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
leading: CircleAvatar(
  radius: 26,
  backgroundColor: const Color(0xFF1B8A83),
  backgroundImage: AssetImage(
    switch (data['memberName']?.toString().trim()) {
      'कमला देउजा' => 'assets/member1.jpg',
      'हरि कुमार चौहान' => 'assets/member2.jpg',
      'बाल कुमार चौहान' => 'assets/member3.jpg',
      'चन्द्र बहादुर चौहान' => 'assets/member4.jpg',
      'टिकाराम चौहान' => 'assets/member5.jpg',
      'उदय चौहान' => 'assets/member6.jpg',
      _ => 'assets/official_logo.png',
    },
  ),
),
                        title: Text(
                          data['memberName']?.toString() ?? 'नाम छैन',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'रकम: रु. $amount\n'
                          'भुक्तानी प्रकार: ${data['paymentType'] ?? '-'}\n'
                          'BS मिति: ${toNepaliDigits(data['bsDate']?.toString() ?? '-')}\n'
                          'AD मिति: ${data['adDate'] ?? '-'}',
                        ),
                        isThreeLine: true,
                        trailing: const Chip(
                          label: Text('Pending'),
                        ),
                      ),
                      Text(
                        dateText,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _approve(
                                context,
                                doc.id,
                                amount,
                                adminUid,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('स्वीकृत / रकम सच्याउने'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _reject(
                              context,
                              doc.id,
                              adminUid,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('अस्वीकार'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminApprovedLoansPage extends StatefulWidget {
  const AdminApprovedLoansPage({super.key});

  @override
  State<AdminApprovedLoansPage> createState() =>
      _AdminApprovedLoansPageState();
}

class _AdminApprovedLoansPageState
    extends State<AdminApprovedLoansPage> {
    
    Timer? _interestTimer;

@override
void initState() {
  super.initState();

  _interestTimer = Timer.periodic(
    const Duration(minutes: 1),
    (_) {
      if (mounted) {
        setState(() {});
      }
    },
  );
}

@override
void dispose() {
  _interestTimer?.cancel();
  super.dispose();
}
    
String _memberPhoto(String? name) {
  switch (name?.trim()) {
    case 'कमला देउजा':
      return 'assets/member1.jpg';
    case 'हरि कुमार चौहान':
      return 'assets/member2.jpg';
    case 'बाल कुमार चौहान':
      return 'assets/member3.jpg';
    case 'चन्द्र बहादुर चौहान':
      return 'assets/member4.jpg';
    case 'टिकाराम चौहान':
      return 'assets/member5.jpg';
    case 'उदय चौहान':
      return 'assets/member6.jpg';
    default:
      return 'assets/official_logo.png';
  }
}
    String _dateText(dynamic value) {
  if (value is! Timestamp) {
    return 'उपलब्ध छैन';
  }

  final date = value.toDate();
  final bs = NepaliDateTime.fromDateTime(date);

  return toNepaliDigits('${bs.year}/${bs.month.toString().padLeft(2, '0')}/${bs.day.toString().padLeft(2, '0')}');
}
    String _loanExpiryText(Map<String, dynamic> data) {
  final startValue =
      data['disbursedAt'] ?? data['loanStartAt'];

  if (startValue is! Timestamp) {
    return 'उपलब्ध छैन';
  }

  final duration = (
    data['approvedDurationMonths'] ??
    data['durationMonths'] ??
    1
  ) as num;

  final startBs =
      NepaliDateTime.fromDateTime(startValue.toDate());

  final monthIndex = startBs.month - 1 + duration.toInt();
  final targetYear = startBs.year + monthIndex ~/ 12;
  final targetMonth = monthIndex % 12 + 1;

  final lastDay =
      NepaliDateTime(targetYear, targetMonth).totalDays;

  final targetDay =
      startBs.day > lastDay ? lastDay : startBs.day;

  final expiryBs = NepaliDateTime(
    targetYear,
    targetMonth,
    targetDay,
  ).subtract(const Duration(days: 1));

  return toNepaliDigits('${expiryBs.year}/${expiryBs.month.toString().padLeft(2, '0')}/${expiryBs.day.toString().padLeft(2, '0')}');
}
    Map<String, dynamic> _calculateCurrentInterest(
  Map<String, dynamic> data,
) {
  final startValue = data['disbursedAt'] ?? data['loanStartAt'];

  if (startValue is! Timestamp) {
    return {
      'interest': 0.0,
      'totalUnpaid': 0.0,
      'overdueDays': 0,
      'actionRequired': false,
    };
  }

  final principal = (
    data['outstandingPrincipal'] ??
    data['disbursedAmount'] ??
    data['approvedAmount'] ??
    0
  ).toDouble();

  final duration = (
    data['approvedDurationMonths'] ??
    data['durationMonths'] ??
    1
  ) as num;

  final startBs = NepaliDateTime.fromDateTime(
    startValue.toDate(),
  );

  final monthIndex = startBs.month - 1 + duration.toInt();
  final targetYear = startBs.year + monthIndex ~/ 12;
  final targetMonth = monthIndex % 12 + 1;

  final lastDay =
      NepaliDateTime(targetYear, targetMonth).totalDays;

  final targetDay =
      startBs.day > lastDay ? lastDay : startBs.day;

  final expiryBs = NepaliDateTime(
    targetYear,
    targetMonth,
    targetDay,
  ).subtract(const Duration(days: 1));

  final expiryDate = expiryBs.toDateTime();

  final lastInterestValue = data['lastInterestDate'];

  final lastInterestDate = lastInterestValue is Timestamp
      ? lastInterestValue.toDate()
      : startValue.toDate();

  final result = LoanService().calculateLoanInterest(
    principal: principal,
    lastInterestDate: lastInterestDate,
    expiryDate: expiryDate,
    calculationDate: DateTime.now(),
    baseMonthlyRate: (data['monthlyInterestRate'] as num?)?.toDouble(),
    originalLoanAmount: (data['approvedAmount'] ?? data['requestedAmount'] ?? principal) as num,
    useAmountBasedRules: data['monthlyInterestRate'] != null,
  );

  final newInterest = (result['interest'] as num).toDouble();

  final previousUnpaid = (
    data['unpaidInterest'] ?? 0
  ).toDouble();

  return {
    'interest': newInterest,
    'totalUnpaid': previousUnpaid + newInterest,
    'overdueDays': result['overdueDays'],
    'actionRequired': result['actionRequired'],
  };
}
    
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        title: const Text('स्वीकृत ऋण विवरण'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('loans')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('ऋण विवरण लोड हुन सकेन।'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final loans = snapshot.data!.docs
              .where((doc) =>
                  doc.data()['status'] == 'active')
              .toList();

          if (loans.isEmpty) {
            return const Center(
              child: Text('हाल कुनै सक्रिय स्वीकृत ऋण छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: loans.length,
            itemBuilder: (context, index) {
              final data = loans[index].data();

              final amount = data['approvedAmount'] ?? 0;
              final disbursed = data['disbursedAmount'] ?? amount;
              final outstanding =
                  data['outstandingPrincipal'] ?? disbursed;
              final duration =
                  data['approvedDurationMonths'] ??
                  data['durationMonths'] ?? 0;
                final interestData = _calculateCurrentInterest(data);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                     Row(
  children: [
    CircleAvatar(
      radius: 28,
      backgroundImage: AssetImage(
        _memberPhoto(data['memberName']),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: Text(
        data['memberName'] ?? 'नाम उपलब्ध छैन',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ],
),
                        Align(
  alignment: Alignment.centerLeft,
  child: Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 5,
    ),
    decoration: BoxDecoration(
      color: Colors.green.shade100,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'सक्रिय ऋण',
      style: TextStyle(
        color: Colors.green,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  ),
),
const Divider(),
Text('स्वीकृत रकम: रु. $amount'),
 Text('वितरण रकम: रु. $disbursed'),
 Text('बाँकी साँवा: रु. $outstanding'),
Text('थपिएको ब्याज: रु. ${interestData['interest']}'),
Text(
  'कुल बाँकी ब्याज: रु. ${(interestData['totalUnpaid'] as num).toDouble().toStringAsFixed(2)}',
),
 Text('ऋण अवधि: $duration महिना'),

 Text(
     'स्वीकृत मिति: ${_dateText(data['reviewedAt'] ?? data['disbursedAt'])}',
),
 const SizedBox(height: 8),
                        
                        Text(
  'ऋण चुक्ता गर्नुपर्ने मिति: ${_loanExpiryText(data)}',
),
             
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

  class LoanAdminMenuPage extends StatelessWidget {
  const LoanAdminMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final menus = [
      (
        'ऋण आवेदन तथा स्वीकृति',
        Icons.assignment_outlined,
      ),
      (
        'स्वीकृत ऋण विवरण',
        Icons.account_balance_wallet_outlined,
      ),
      (
        'किस्ता स्वीकृति',
        Icons.fact_check_outlined,
      ),
      (
        'किस्ता इतिहास',
        Icons.history,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        title: const Text('ऋण व्यवस्थापन'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: menus.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                backgroundColor: navy.withOpacity(0.1),
                child: Icon(
                  menus[index].$2,
                  color: navy,
                ),
              ),
              title: Text(
                menus[index].$1,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 17,
              ),
             onTap: () {
  if (index == 0) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoanManagementPage(),
      ),
    );
  } else if (index == 1) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminApprovedLoansPage(),
      ),
    );
  } else if (index == 2) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          const AdminInstallmentApprovalPage(),
    ),
  );
} else {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('किस्ता इतिहास अर्को चरणमा जोडिनेछ।'),
    ),
  );
}
},
            ),
          );
        },
      ),
    );
  }
}

class AdminInstallmentApprovalPage extends StatelessWidget {
  const AdminInstallmentApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('किस्ता स्वीकृति'),
      ),
      body: StreamBuilder(
        stream: LoanService().watchPendingInstallments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('त्रुटि: ${snapshot.error}'),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const Center(
              child: Text('स्वीकृतिका लागि कुनै किस्ता आएको छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              final data = doc.data();

              final memberName =
              data['memberName'] ?? 'नाम उपलब्ध छैन';
 final amount = data['amount'] ?? 0;
final amountController = TextEditingController(
  text: amount.toString(),
);
              final paymentDate =
                  data['paymentBsDate'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName.toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
  TextField(
  controller: amountController,
  keyboardType: TextInputType.number,
  decoration: const InputDecoration(
    labelText: 'स्वीकृत गर्नुपर्ने किस्ता रकम',
    prefixText: 'रु. ',
    border: OutlineInputBorder(),
  ),
),
  Text('भुक्तानी मिति: ${toNepaliDigits(paymentDate)}'),
  const SizedBox(height: 12),

if (data['receiptBase64'] != null &&
    data['receiptBase64'].toString().isNotEmpty) ...[
  const Text(
    'भुक्तानी भौचर:',
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 15,
    ),
  ),
  const SizedBox(height: 8),
  GestureDetector(
    onTap: () {
      showDialog(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            child: InteractiveViewer(
              child: Image.memory(
                base64Decode(data['receiptBase64']),
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      );
    },
    child: Image.memory(
      base64Decode(data['receiptBase64']),
      height: 180,
      width: double.infinity,
      fit: BoxFit.contain,
    ),
  ),
] else ...[
  const Text(
    'भौचर फोटो उपलब्ध छैन।',
    style: TextStyle(color: Colors.red),
  ),
],
  const SizedBox(height: 14),
  Row(
  children: [
  Expanded(
  child: ElevatedButton(
  style: ElevatedButton.styleFrom(
  backgroundColor: Colors.green,
  foregroundColor: Colors.white,
  ),
  onPressed: () async {
  final confirm =
  await showDialog<bool>(
  context: context,
  builder: (dialogContext) {
  return AlertDialog(
  title: const Text(
 'किस्ता स्वीकृत गर्ने?',
  ),
  content: const Text(
  'यो किस्ता स्वीकृत गर्न चाहनुहुन्छ?',
   ),
   actions: [
   TextButton(
   onPressed: () =>
   Navigator.pop(
  dialogContext,
  false,
  ),
  child: const Text('रद्द'),
  ),
  ElevatedButton(
 onPressed: () =>
                                              Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                          child: const Text('स्वीकृत'),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (confirm != true) return;

   try {
 final adjustedAmount = double.tryParse(
  amountController.text.trim(),
);

if (adjustedAmount == null || adjustedAmount <= 0) {
  throw Exception('कृपया सही किस्ता रकम राख्नुहोस्।');
}

await LoanService().approveLoanInstallment(
  installmentId: doc.id,
  adjustedAmount: adjustedAmount,
);

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'किस्ता सफलतापूर्वक स्वीकृत भयो।',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'त्रुटि: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('स्वीकृत'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final confirm =
                                    await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) {
                                    return AlertDialog(
                                      title: const Text(
                                        'किस्ता अस्वीकृत गर्ने?',
                                      ),
                                      content: const Text(
                                        'यो किस्ता अस्वीकृत गर्न चाहनुहुन्छ?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                          child: const Text('रद्द'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                          child: const Text('अस्वीकृत'),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (confirm != true) return;

                                try {
                                  await LoanService()
                                      .rejectLoanInstallment(
                                    installmentId: doc.id,
                                  );

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'किस्ता अस्वीकृत गरियो।',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'त्रुटि: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('अस्वीकृत'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LoanManagementPage extends StatelessWidget {
  const LoanManagementPage({super.key});

  String _memberPhoto(String? name) {
    switch (name?.trim()) {
      case 'कमला देउजा':
        return 'assets/member1.jpg';
      case 'हरि कुमार चौहान':
        return 'assets/member2.jpg';
      case 'बाल कुमार चौहान':
        return 'assets/member3.jpg';
      case 'चन्द्र बहादुर चौहान':
        return 'assets/member4.jpg';
      case 'टिकाराम चौहान':
        return 'assets/member5.jpg';
      case 'उदय चौहान':
        return 'assets/member6.jpg';
      default:
        return 'assets/official_logo.png';
    }
  }
    

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        title: const Text('ऋण व्यवस्थापन'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: LoanService().watchPendingLoans(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'ऋण आवेदन लोड भएन। Firebase Rules जाँच गर्नुहोस्।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: navy.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: navy,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'ऋण आवेदन छैन',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'हालसम्म कुनै सदस्यले ऋण आवेदन पेस गर्नुभएको छैन।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFF687386),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'नयाँ आवेदन आएपछि यहाँ देखिनेछ',
              style: TextStyle(
                color: navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final loanId = docs[index].id;
              final amount =
                  (data['requestedAmount'] as num?)?.toInt() ?? 0;

              final submittedAt = data['submittedAt'] as Timestamp?;
              final submittedText = submittedAt == null
                  ? 'पेस गरिएको समय: उपलब्ध छैन'
                  : 'पेस गरिएको: ${submittedAt.toDate().toLocal()}';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundImage: AssetImage(
                            _memberPhoto(
                              data['memberName']?.toString(),
                            ),
                          ),
                        ),
                        title: Text(
                          data['memberName']?.toString() ?? 'नाम छैन',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'माग गरिएको ऋण: रु. $amount\n'
                          'BS मिति: ${toNepaliDigits(data['bsDate'] ?? '-')}\n'
                          'AD मिति: ${data['adDate'] ?? '-'}',
                        ),
                        isThreeLine: true,
                        trailing: const Chip(
                          label: Text('Pending'),
                        ),
                      ),
                      const Divider(),
                      const Text(
                        'ऋण लिनुको कारण:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(data['purpose']?.toString() ?? '-'),
                      const SizedBox(height: 8),
                      Text(
                        submittedText,
                        style: const TextStyle(fontSize: 12),
                      ),
const SizedBox(height: 12),

StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: LoanService().watchGuarantorResponses(loanId),
  builder: (context, voteSnapshot) {
    if (voteSnapshot.hasError) {
      return const Text(
        'मतदान विवरण लोड भएन।',
        style: TextStyle(color: Colors.red),
      );
    }

    if (voteSnapshot.connectionState ==
        ConnectionState.waiting) {
      return const LinearProgressIndicator();
    }

    final round =
        (data['votingRound'] as num?)?.toInt() ?? 1;

    final voterUids =
        List<String>.from(data['voterUids'] ?? <String>[]);

    final seen = <String>{};
    var agree = 0;
    var disagree = 0;

    for (final voteDoc in voteSnapshot.data?.docs ?? []) {
      final vote = voteDoc.data();
      final uid = vote['voterUid']?.toString();
      final voteRound =
          (vote['round'] as num?)?.toInt() ?? 1;

      if (uid == null ||
          !voterUids.contains(uid) ||
          voteRound != round ||
          !seen.add(uid)) {
        continue;
      }

      if (vote['vote'] == 'agree') {
        agree++;
      } else if (vote['vote'] == 'disagree') {
        disagree++;
      }
    }

    final remaining = voterUids.length - seen.length;
      final allVoted =
    voterUids.length == 5 && remaining == 0;

final isVoting = data['status'] == 'voting';
      
final isAdminReview = data['status'] == 'admin_review';
final isAdminPending = data['status'] == 'admin_pending';
      
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'मतदान विवरण',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: navy,
            ),
          ),
          const SizedBox(height: 8),
          Text('जम्मा मतदानकर्ता: ${voterUids.length} जना'),
          Text(
            'सहमति: $agree जना',
            style: const TextStyle(color: Colors.green),
          ),
          Text(
            'असहमति: $disagree जना',
            style: const TextStyle(color: Colors.red),
          ),
          Text(
            'मतदान गर्न बाँकी: $remaining जना',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
            const SizedBox(height: 12),

if (isVoting)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: allVoted
          ? () async {
              final adminUid =
                  FirebaseAuth.instance.currentUser?.uid;

              if (adminUid == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Admin लगइन भेटिएन।'),
                  ),
                );
                return;
              }

              try {
                await LoanService().processLoanVotes(
                  loanId: loanId,
                  adminUid: adminUid,
                );

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('मतगणना सफल भयो।'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('मतगणना हुन सकेन: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          : null,
      icon: const Icon(Icons.how_to_vote),
      label: const Text('मतगणना गर्नुहोस्'),
    ),
  ),
            if (isAdminReview)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () async {
  final amountController = TextEditingController(
    text: amount.toString(),
  );

  final durationController = TextEditingController(
    text: (data['durationMonths'] ?? 1).toString(),
  );

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('ऋण आवेदन संशोधन'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'संशोधित ऋण रकम (रु.)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ऋण अवधि (महिना)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('रद्द गर्नुहोस्'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('दोस्रो मतदानमा पठाउनुहोस्'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    amountController.dispose();
    durationController.dispose();
    return;
  }

  final revisedAmount =
      int.tryParse(amountController.text.trim());

  final revisedDuration =
      int.tryParse(durationController.text.trim());

  amountController.dispose();
  durationController.dispose();

  if (revisedAmount == null ||
      revisedAmount <= 0 ||
      revisedDuration == null ||
      revisedDuration < 1 ||
      revisedDuration > 12) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ऋण रकम वा अवधि सही राख्नुहोस्।'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final adminUid = FirebaseAuth.instance.currentUser?.uid;

  if (adminUid == null) return;

  try {
    await LoanService().startSecondVoting(
      loanId: loanId,
      adminUid: adminUid,
      revisedAmount: revisedAmount,
      revisedDurationMonths: revisedDuration,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('संशोधित आवेदन दोस्रो मतदानमा पठाइयो।'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('दोस्रो मतदान सुरु हुन सकेन: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
},
      icon: const Icon(Icons.edit),
      label: const Text('ऋण आवेदन सम्पादन / दोस्रो मतदान'),
      style: ElevatedButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
    ),
  ),
            if (isAdminPending)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () async {
        final amountController = TextEditingController(
          text: amount.toString(),
        );

        final durationController = TextEditingController(
          text: (data['durationMonths'] ?? 1).toString(),
        );

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ऋणको अन्तिम स्वीकृति'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'स्वीकृत ऋण रकम (रु.)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ऋण अवधि (महिना)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, false),
                child: const Text('रद्द'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, true),
                child: const Text('स्वीकृत गर्नुहोस्'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          amountController.dispose();
          durationController.dispose();
          return;
        }

        final approvedAmount =
            int.tryParse(amountController.text.trim());
        final approvedDuration =
            int.tryParse(durationController.text.trim());

        amountController.dispose();
        durationController.dispose();

        if (approvedAmount == null ||
            approvedAmount <= 0 ||
            approvedDuration == null ||
            approvedDuration < 1 ||
            approvedDuration > 12) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('रकम वा अवधि सही राख्नुहोस्।'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final adminUid =
            FirebaseAuth.instance.currentUser?.uid;

        if (adminUid == null) return;

        try {
          await LoanService().approveLoan(
            loanId: loanId,
            approvedBy: adminUid,
            approvedAmount: approvedAmount,
            approvedDurationMonths: approvedDuration,
          );

          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ऋण सफलतापूर्वक स्वीकृत भयो।'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ऋण स्वीकृत हुन सकेन: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      icon: const Icon(Icons.verified_outlined),
      label: const Text('ऋण अन्तिम रूपमा स्वीकृत गर्नुहोस्'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    ),
  ),
        ],
      ),
    );
  },
),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ExpenseWithdrawalVotingPage extends StatelessWidget {
  final String uid;

  const ExpenseWithdrawalVotingPage({
    super.key,
    required this.uid,
  });

  Future<void> _submitVote(
    BuildContext context,
    String proposalId,
    bool approve,
  ) async {
    try {
      await ExpenseWithdrawalService().castVote(
        proposalId: proposalId,
        approve: approve,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('तपाईंको मतदान सफल भयो।'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('मतदान हुन सकेन: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  backgroundColor: const Color(0xFFFFF3E0),
  appBar: AppBar(
    backgroundColor: const Color(0xFFEF6C00),
    foregroundColor: Colors.white,
    title: const Text('खर्च प्रस्ताव मतदान'),
  ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('expense_withdrawal_proposals')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('खर्च प्रस्ताव लोड हुन सकेन।'),
            );
          }

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final now = DateTime.now();

          final proposals = (snapshot.data?.docs ?? [])
    .where((doc) {
  final data = doc.data();
  final eligibleUids =
      List<String>.from(
    data['eligibleVoterUids'] ?? [],
  );

  return eligibleUids.contains(uid);
}).toList();

          if (proposals.isEmpty) {
            return const Center(
              child: Text(
                'हाल मतदान गर्नुपर्ने खर्च प्रस्ताव छैन।',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            );
          }

          proposals.sort((a, b) {
            final aDate =
                a.data()['submittedAt'] as Timestamp?;
            final bDate =
                b.data()['submittedAt'] as Timestamp?;

            return (bDate?.compareTo(
                  aDate ?? Timestamp(0, 0),
                ) ??
                0);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: proposals.length,
            itemBuilder: (context, index) {
              final proposal = proposals[index];
              final data = proposal.data();

              return StreamBuilder<
                  DocumentSnapshot<Map<String, dynamic>>>(
                stream: proposal.reference
                    .collection('votes')
                    .doc(uid)
                    .snapshots(),
                builder: (context, voteSnapshot) {
                  final hasVoted =
                      voteSnapshot.data?.exists ?? false;

                  return Card(
  color: const Color(0xFF1E3A5F),
  elevation: 3,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: const BorderSide(
      color: Color(0xFFFFCC80),
      width: 1,
    ),
  ),
  margin: const EdgeInsets.only(
    bottom: 12,
  ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data['title'] ??
                                    'खर्च प्रस्ताव')
                                .toString(),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
    'श्रेणी: ${data['category'] ?? '-'}',
                          ),
                          Text(
   'प्रस्तावित रकम: रु. ${data['amount'] ?? 0}',
                          ),
                          Text(
 'विवरण: ${data['description'] ?? '-'}',
         ),
   const SizedBox(height: 8),
Text(
  'अवस्था: ${{
    'voting': 'मतदान जारी',
    'approved': 'खर्च स्वीकृत',
    'rejected': 'खर्च अस्वीकृत',
    'disbursed': 'रकम निकासी भयो',
  }[data['status']] ?? 'अन्य'}',
  style: TextStyle(
  color: data['status'] == 'disbursed'
      ? Colors.green
      : data['status'] == 'approved'
          ? Colors.yellow
          : data['status'] == 'rejected'
              ? Colors.red
              : Colors.amber,
  fontWeight: FontWeight.bold,
  fontSize: 15,
),
),
   
const SizedBox(height: 8),


 // Proposal Voucher
if ((data['proposalVoucherFileName'] ??
        (data['paymentVoucherFileName'] == null
            ? data['voucherFileName']
            : null) ??
        '')
    .toString()
    .isNotEmpty)
  InkWell(
    onTap: () async {
      final url = (data['proposalVoucherUrl'] ??
              (data['paymentVoucherUrl'] == null
                  ? data['voucherUrl']
                  : null))
          .toString();
      if (url.isNotEmpty) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
    },
    child: Text(
      'प्रस्तावको Voucher: ${data['proposalVoucherFileName'] ?? (data['paymentVoucherFileName'] == null ? data['voucherFileName'] : '')} (खोल्नुहोस्)',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline,
      ),
    ),
  ),

if ((data['proposalVoucherUrl'] ??
        (data['paymentVoucherUrl'] == null
            ? data['voucherUrl']
            : null) ??
        '')
        .toString()
        .isNotEmpty &&
    !((data['proposalVoucherFileName'] ??
                (data['paymentVoucherFileName'] == null
                    ? data['voucherFileName']
                    : null) ??
                '')
            .toString()
            .toLowerCase()
            .endsWith('.pdf')))
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Image.network(
      (data['proposalVoucherUrl'] ??
              (data['paymentVoucherUrl'] == null
                  ? data['voucherUrl']
                  : null))
          .toString(),
      height: 160,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'Proposal Voucher देखाउन सकिएन।',
          style: TextStyle(color: Colors.white),
        );
      },
    ),
  ),


if ((data['paymentVoucherFileName'] ?? '').toString().isNotEmpty)
  InkWell(
    onTap: () async {
      final url = (data['paymentVoucherUrl'] ?? '').toString();
      if (url.isNotEmpty) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
    },
    child: Text(
      'भुक्तानीको Voucher: ${data['paymentVoucherFileName']} (खोल्नुहोस्)',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline,
      ),
    ),
  ),

if ((data['paymentVoucherUrl'] ?? '')
        .toString()
        .isNotEmpty &&
    !(data['paymentVoucherFileName'] ?? '')
        .toString()
        .toLowerCase()
        .endsWith('.pdf'))
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Image.network(
      data['paymentVoucherUrl'].toString(),
      height: 160,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'Payment Voucher देखाउन सकिएन।',
          style: TextStyle(color: Colors.white),
        );
      },
    ),
  ),

  const SizedBox(height: 12),
 if (voteSnapshot.connectionState ==
                              ConnectionState.waiting)
  const Center(
  child: CircularProgressIndicator(),
     )
  else if (hasVoted)
  Text(
    voteSnapshot.data?.data()?['vote'] == 'yes'
        ? 'तपाईंले स्वीकृत मत दिनुभएको छ।'
        : 'तपाईंले अस्वीकृत मत दिनुभएको छ।',
    style: TextStyle(
      color: voteSnapshot.data?.data()?['vote'] == 'yes'
          ? Colors.green
          : Colors.red,
      fontWeight: FontWeight.bold,
      fontSize: 15,
    ),
  )
        else
         Row(
         children: [
        Expanded(
       child: ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green,
    foregroundColor: Colors.white,
  ),
  onPressed: () => _submitVote(
    context,
    proposal.id,
    true,
  ),
  child: const Text('स्वीकृत'),
),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
   child: ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.red,
    foregroundColor: Colors.white,
  ),
  onPressed: () => _submitVote(
    context,
    proposal.id,
    false,
  ),
  child: const Text('अस्वीकृत'),
),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
