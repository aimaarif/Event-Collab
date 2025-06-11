import 'dart:async';
import 'package:flutter/material.dart';
import 'package:event_collab/screens/home_screen.dart';
import 'package:event_collab/auth_service.dart';
import 'package:event_collab/screens/auth_screen.dart'; // Import the new AuthScreen

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    Timer(Duration(seconds: 3), () {
      // Check if user is already signed in
      if (_authService.isUserSignedIn()) {
        // Go to home screen if already signed in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        // Go to auth screen if not signed in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AuthScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/logo.png",
              width: 150,
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}