import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:event_collab/auth_service.dart';
import 'package:event_collab/screens/home_screen.dart';
import 'package:event_collab/screens/profile_setup_screen.dart'; // Add this import

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _resetPasswordFormKey = GlobalKey<FormState>();

  bool _isLogin = true; // Toggle between login and signup
  bool _isLoading = false;
  bool _isResetting = false;
  String _email = '';
  String _password = '';
  String _resetEmail = '';
  String? _errorMessage;
  String? _resetErrorMessage;
  String? _resetSuccessMessage;

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
    });
  }

  // Navigate to the appropriate screen after authentication
  Future<void> _navigateAfterAuth(User user) async {
    try {
      // Check if profile setup is complete
      bool isProfileComplete = await _authService.isProfileSetupComplete(user.uid);

      if (mounted) {
        if (isProfileComplete) {
          // If profile is complete, go to home screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        } else {
          // If profile is not complete, go to profile setup
          // Also create the initial user document if it doesn't exist
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'profileSetupComplete': false,
            'userName': '',
            'role': '',
          }, SetOptions(merge: true));

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfileSetupScreen()),
          );
        }
      }
    } catch (e) {
      print('Error navigating after auth: $e');
      // Fallback to home screen if there's an error
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    _formKey.currentState!.save();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      User? user;
      if (_isLogin) {
        user = await _authService.signInWithEmailPassword(_email, _password);
      } else {
        user = await _authService.signUpWithEmailPassword(_email, _password);
      }

      if (user != null && mounted) {
        _navigateAfterAuth(user);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred, please check your credentials';

      if (e.code == 'user-not-found') {
        message = 'No user found with this email';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password';
      } else if (e.code == 'email-already-in-use') {
        message = 'This email is already registered';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      }

      setState(() {
        _errorMessage = message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Please try again later.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final User? user = await _authService.signInWithGoogle();

      if (user != null && mounted) {
        _navigateAfterAuth(user);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to sign in with Google. Please try again.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  // Show dialog for password reset
  void _showResetPasswordDialog() {
    setState(() {
      _resetEmail = _email; // Pre-fill with current email if available
      _resetErrorMessage = null;
      _resetSuccessMessage = null;
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Reset Password'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter your email address to receive a password reset link.'),
                  SizedBox(height: 16),

                  if (_resetErrorMessage != null)
                    Container(
                      padding: EdgeInsets.all(8),
                      color: Colors.red.shade50,
                      width: double.infinity,
                      child: Text(
                        _resetErrorMessage!,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),

                  if (_resetSuccessMessage != null)
                    Container(
                      padding: EdgeInsets.all(8),
                      color: Colors.green.shade50,
                      width: double.infinity,
                      child: Text(
                        _resetSuccessMessage!,
                        style: TextStyle(color: Colors.green),
                      ),
                    ),

                  SizedBox(height: 16),

                  Form(
                    key: _resetPasswordFormKey,
                    child: TextFormField(
                      initialValue: _resetEmail,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        _resetEmail = value.trim();
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Cancel'),
              ),
              _isResetting
                  ? CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: () async {
                  if (_resetPasswordFormKey.currentState!.validate()) {
                    setDialogState(() {
                      _isResetting = true;
                      _resetErrorMessage = null;
                      _resetSuccessMessage = null;
                    });

                    try {
                      await _authService.resetPassword(_resetEmail);
                      setDialogState(() {
                        _isResetting = false;
                        _resetSuccessMessage = 'Password reset email sent. Please check your inbox.';
                      });

                      // Close dialog after a delay
                      Future.delayed(Duration(seconds: 3), () {
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      });
                    } on FirebaseAuthException catch (e) {
                      String message = 'Failed to send reset email';

                      if (e.code == 'user-not-found') {
                        message = 'No user found with this email';
                      } else if (e.code == 'invalid-email') {
                        message = 'Invalid email address';
                      }

                      setDialogState(() {
                        _isResetting = false;
                        _resetErrorMessage = message;
                      });
                    } catch (e) {
                      setDialogState(() {
                        _isResetting = false;
                        _resetErrorMessage = 'Something went wrong. Please try again later.';
                      });
                    }
                  }
                },
                child: Text('Send Reset Link'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              Image.asset(
                'assets/logo.png',
                height: 100,
              ),
              SizedBox(height: 32),

              // Title
              Text(
                _isLogin ? 'Login' : 'Create Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),

              // Error message if any
              if (_errorMessage != null)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  color: Colors.red.shade50,
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(height: _errorMessage != null ? 16 : 0),

              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email field
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        _email = value!.trim();
                      },
                      onChanged: (value) {
                        _email = value.trim();
                      },
                    ),
                    SizedBox(height: 16),

                    // Password field
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (!_isLogin && value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        _password = value!;
                      },
                    ),
                    SizedBox(height: 24),

                    // Submit button
                    _isLoading
                        ? CircularProgressIndicator()
                        : ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _isLogin ? 'Login' : 'Sign Up',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Forgot password (only in login mode)
                    if (_isLogin)
                      TextButton(
                        onPressed: _showResetPasswordDialog,
                        child: Text('Forgot Password?'),
                      ),

                    // Toggle between login and signup
                    TextButton(
                      onPressed: _toggleAuthMode,
                      child: Text(
                        _isLogin
                            ? 'New User? Create Account'
                            : 'Already have an account? Login',
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // OR divider
              Row(
                children: [
                  Expanded(
                    child: Divider(thickness: 1),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(thickness: 1),
                  ),
                ],
              ),

              SizedBox(height: 24),

              // Google Sign In button
              OutlinedButton.icon(
                onPressed: _signInWithGoogle,
                icon: Image.asset(
                  'assets/google_logo.png',
                  height: 24,
                  width: 24,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.g_mobiledata),
                ),
                label: Text('Sign in with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}