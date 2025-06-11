import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../cloudinary_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentFormPage extends StatefulWidget {
  final String eventId;

  const PaymentFormPage({Key? key, required this.eventId}) : super(key: key);

  @override
  _PaymentFormPageState createState() => _PaymentFormPageState();
}

class _PaymentFormPageState extends State<PaymentFormPage> {
  File? _selectedImage;
  bool _isUploading = false;
  List<String> accountNumbers = [];
  List<String> bankNames = [];  // Add this line
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();
  // Instance of your cloudinary service
  final CloudinaryService _cloudinaryService = CloudinaryService();

  @override
  void initState() {
    super.initState();
    _fetchPaymentInfo();
  }

  Future<void> _fetchPaymentInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (eventDoc.exists) {
        var data = eventDoc.data() as Map<String, dynamic>;
        if (data.containsKey('accountNumbers') && data['accountNumbers'] is List) {
          setState(() {
            accountNumbers = List<String>.from(data['accountNumbers']);
          });
        }
        // Add this block to fetch bank names
        if (data.containsKey('bankNames') && data['bankNames'] is List) {
          setState(() {
            bankNames = List<String>.from(data['bankNames']);
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading payment information: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitPayment() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment screenshot')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Get current user ID and email
      final User? currentUser = FirebaseAuth.instance.currentUser;
      final String? userId = currentUser?.uid;
      final String? userEmail = currentUser?.email;

      // Check if user is authenticated
      if (userId == null) {
        throw Exception('You must be logged in to submit a payment');
      }

      // Check if file exists and is readable
      if (!await _selectedImage!.exists()) {
        throw Exception('Selected image file does not exist');
      }

      print('Attempting to upload payment screenshot to Cloudinary');

      // Use your cloudinary service to upload the image
      final String? downloadUrl = await _cloudinaryService.uploadImage(_selectedImage!);

      // If downloadUrl is null, the upload failed
      if (downloadUrl == null) {
        throw Exception('Failed to upload image to Cloudinary - no URL returned');
      }

      print('Successfully uploaded image to: $downloadUrl');

      // Get event name
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      String eventName = 'Unnamed Event';
      if (eventDoc.exists) {
        var eventData = eventDoc.data() as Map<String, dynamic>;
        eventName = eventData['name'] as String? ?? 'Unnamed Event';
      }

      // Save payment record to Firestore with userId, userEmail, and eventName
      await FirebaseFirestore.instance.collection('payments').add({
        'eventId': widget.eventId,
        'userId': userId,
        'userEmail': userEmail,  // Add user email
        'eventName': eventName,  // Add event name
        'screenshotUrl': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      print('Payment record added to Firestore');

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment information submitted successfully')),
        );

        // Navigate back to event detail page
        Navigator.pop(context, true); // true indicates successful submission
      }
    } catch (e) {
      print('Payment submission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting payment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Information'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Details',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Display account numbers
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please send payment to one of these accounts:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (accountNumbers.isEmpty)
                      const Text(
                        'No account numbers available',
                        style: TextStyle(
                          color: Colors.red,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: accountNumbers.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Card(
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Display bank name if available
                                    if (index < bankNames.length && bankNames[index].isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4.0),
                                        child: Row(
                                          children: [
                                            Icon(Icons.account_balance, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              bankNames[index],
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Display account number
                                    Row(
                                      children: [
                                        Icon(Icons.credit_card, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            accountNumbers[index],
                                            style: TextStyle(fontSize: 16),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.copy),
                                          onPressed: () {
                                            // Copy account number to clipboard
                                            // This requires clipboard package
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Account number copied to clipboard'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
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
            ),

            const SizedBox(height: 24),

            // Upload payment screenshot section
            const Text(
              'Upload Payment Screenshot',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Image preview
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _selectedImage!,
                  fit: BoxFit.cover,
                ),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.image,
                    size: 50,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No image selected',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Upload button
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickImage,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select Screenshot'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 24),

            // Submit button
            ElevatedButton(
              onPressed: _isUploading ? null : _submitPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isUploading
                  ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Uploading...'),
                ],
              )
                  : const Text('Submit Payment'),
            ),
          ],
        ),
      ),
    );
  }
}