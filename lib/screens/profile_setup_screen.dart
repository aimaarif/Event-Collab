import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:event_collab/screens/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  String _userName = '';
  String _selectedRole = 'Attendee';
  String? _errorMessage;

  // List of available roles
  final List<String> _roles = [
    'Attendee',
    'Organizer',
    'Sponsor',
    'Vendor',
    'Volunteer'
  ];

  // Function to check if a username already exists
  Future<bool> _isUsernameAvailable(String username) async {
    try {
      // Query Firestore to check if username exists
      final QuerySnapshot result = await FirebaseFirestore.instance
          .collection('users')
          .where('userName', isEqualTo: username)
          .limit(1)
          .get();

      // If there are no documents with this username, it's available
      return result.docs.isEmpty;
    } catch (e) {
      print('Error checking username availability: $e');
      return false; // Return false on error to be safe
    }
  }

  // Debounced username validation
  Future<String?> _validateUsername(String? value) async {
    if (value == null || value.isEmpty) {
      return 'Please enter a username';
    }

    setState(() {
      _isCheckingUsername = true;
    });

    final isAvailable = await _isUsernameAvailable(value.trim());

    setState(() {
      _isCheckingUsername = false;
    });

    if (!isAvailable) {
      return 'Username is already taken';
    }
    return null;
  }

  Future<void> _saveProfile() async {
    // First check if username is available again (final check)
    final isAvailable = await _isUsernameAvailable(_userName);
    if (!isAvailable) {
      setState(() {
        _errorMessage = 'Username is already taken. Please choose another one.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    _formKey.currentState!.save();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Update Firestore document with profile information
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'userName': _userName,
          'role': _selectedRole,
          'profileSetupComplete': true,
        }, SetOptions(merge: true));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save profile. Please try again.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Set Up Your Profile'),
        automaticallyImplyLeading: false, // Disable back button
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                'Complete Your Profile',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),

              Text(
                'Please provide the following information to set up your profile',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              SizedBox(height: 32),

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
                    // Username field with async validation
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        suffixIcon: _isCheckingUsername
                            ? Container(
                          height: 20,
                          width: 20,
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : null,
                        helperText: 'Username must be unique',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a username';
                        }
                        return null; // We'll do the uniqueness check in onChanged
                      },
                      onSaved: (value) {
                        _userName = value!.trim();
                      },
                      onChanged: (value) async {
                        _userName = value.trim();
                        if (_userName.isNotEmpty) {
                          // Only check if username is not empty
                          String? error = await _validateUsername(_userName);
                          if (error != null) {
                            setState(() {
                              _errorMessage = error;
                            });
                          } else {
                            setState(() {
                              _errorMessage = null;
                            });
                          }
                        }
                      },
                    ),
                    SizedBox(height: 24),

                    // Role dropdown
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Select your role',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.assignment_ind),
                      ),
                      value: _selectedRole,
                      items: _roles.map((String role) {
                        return DropdownMenuItem<String>(
                          value: role,
                          child: Text(
                            role[0].toUpperCase() + role.substring(1),
                            style: TextStyle(fontSize: 16),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedRole = newValue;
                          });
                        }
                      },
                    ),
                    SizedBox(height: 32),

                    // Submit button
                    _isLoading
                        ? CircularProgressIndicator()
                        : ElevatedButton(
                      onPressed: _errorMessage == null ? _saveProfile : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Setup Profile',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}