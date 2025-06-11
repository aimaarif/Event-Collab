import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create or update user document in Firestore
  Future<void> _saveUserToFirestore(User user) async {
    try {
      // Reference to the user document
      final userRef = _firestore.collection('users').doc(user.uid);

      // Check if the user document already exists
      final userDoc = await userRef.get();

      if (!userDoc.exists) {
        // If the document doesn't exist, create it with the user's email
        await userRef.set({
          'email': user.email,
          'createdAt': FieldValue.serverTimestamp(),
          'profileSetupComplete': false,
        });
        print('User document created in Firestore for ${user.email}');
      } else {
        // Document already exists, no need to create it again
        print('User document already exists for ${user.email}');
      }
    } catch (e) {
      print('Error saving user to Firestore: $e');
      // Don't throw the error as this is a secondary operation
      // The user is already authenticated at this point
    }
  }

  // Email/Password Sign Up
  Future<User?> signUpWithEmailPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save user data to Firestore after successful sign up
      if (userCredential.user != null) {
        await _saveUserToFirestore(userCredential.user!);
      }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Email/Password Sign Up Error: ${e.code} - ${e.message}");
      throw e; // Rethrow to handle in UI
    } catch (e) {
      print("Unexpected error during sign up: $e");
      throw e;
    }
  }

  // Email/Password Sign In
  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // For email/password sign in, we could also save user data
      // but it's typically not necessary as it would have been saved during sign up
      // Uncomment if you want to ensure the document exists on every sign in
      // if (userCredential.user != null) {
      //   await _saveUserToFirestore(userCredential.user!);
      // }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Email/Password Sign In Error: ${e.code} - ${e.message}");
      throw e; // Rethrow to handle in UI
    } catch (e) {
      print("Unexpected error during sign in: $e");
      throw e;
    }
  }

  // Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      // Force clear any previous sign-in state
      await _googleSignIn.signOut();

      // Start interactive sign in process
      final GoogleSignInAccount? gUser = await _googleSignIn.signIn();

      // Early return if the sign-in was canceled
      if (gUser == null) {
        print("Google Sign In was canceled by user");
        return null;
      }

      // Obtain auth details
      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      // Create credential
      print("Access token obtained: ${gAuth.accessToken != null}");
      print("ID token obtained: ${gAuth.idToken != null}");
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      // Sign in with Firebase
      try {
        final userCredential = await _auth.signInWithCredential(credential);
        print("Firebase auth successful: ${userCredential.user?.uid}");

        // Save user data to Firestore after successful Google sign in
        if (userCredential.user != null) {
          await _saveUserToFirestore(userCredential.user!);
        }

        return userCredential.user;
      } on FirebaseAuthException catch (authError) {
        print("Firebase Auth Error: $authError");
        return null;
      }
    } catch (e) {
      print("Google Sign In Process Error: $e");
      return null;
    }
  }

  // Password Reset
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      print("Password Reset Error: ${e.code} - ${e.message}");
      throw e;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      print("Sign out complete");
    } catch (e) {
      print("Error signing out: $e");
    }
  }

  // Helper to check authentication state
  bool isUserSignedIn() {
    return _auth.currentUser != null;
  }

  // Get current user info
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<bool> isProfileSetupComplete(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final data = userDoc.data();
        return data != null && data['profileSetupComplete'] == true;
      }

      // If document doesn't exist, profile setup is not complete
      return false;
    } catch (e) {
      print('Error checking profile status: $e');
      return false;
    }
  }
}