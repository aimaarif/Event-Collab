import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class EventApplicationsPage extends StatefulWidget {
  final String eventId;
  final String eventName;

  const EventApplicationsPage({
    Key? key,
    required this.eventId,
    required this.eventName,
  }) : super(key: key);

  @override
  _EventApplicationsPageState createState() => _EventApplicationsPageState();
}

class _EventApplicationsPageState extends State<EventApplicationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Applications for ${widget.eventName}'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getApplicationsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Print full error details
            print('FULL ERROR DETAILS: ${snapshot.error}');
            print('STACK TRACE: ${snapshot.stackTrace}');

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error loading applications'),
                  SizedBox(height: 10),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No applications found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final application = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final applicationId = snapshot.data!.docs[index].id;
              return _buildApplicationCard(application, applicationId);
            },
          );
        },
      ),
    );
  }

  Stream<QuerySnapshot> _getApplicationsStream() {
    return _firestore
        .collection('event_applications')
        .where('eventId', isEqualTo: widget.eventId)
        .orderBy('appliedAt', descending: true)
        .snapshots();
  }

  Widget _buildApplicationCard(Map<String, dynamic> application, String applicationId) {
    final String name = application['name'] ?? 'No name provided';
    final String email = application['userEmail'] ?? 'No email provided';
    final String contactInfo = application['contactInfo'] ?? 'No contact info provided';
    final String message = application['message'] ?? 'No message provided';
    final String role = application['role'] ?? 'Unknown role';
    final String status = application['status'] ?? 'pending';
    final Timestamp? appliedAt = application['appliedAt'] as Timestamp?;

    final String formattedDate = appliedAt != null
        ? DateFormat('MMM dd, yyyy - hh:mm a').format(appliedAt.toDate())
        : 'Unknown date';

    // Determine status color
    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Role chip
                Chip(
                  label: Text(role),
                  backgroundColor: Colors.purple[50],
                  labelStyle: TextStyle(color: Colors.purple[800]),
                ),
                SizedBox(width: 8),
                // Status chip
                Chip(
                  label: Text(status),
                  backgroundColor: statusColor.withOpacity(0.1),
                  labelStyle: TextStyle(color: statusColor),
                ),
                Spacer(),
                // Application date
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Applicant info
            _buildInfoRow(Icons.person, 'Name', name, null),
            _buildInfoRow(Icons.email, 'Email', email, 'email'),
            _buildInfoRow(Icons.phone, 'Contact', contactInfo, 'contact'),

            SizedBox(height: 16),

            // Message
            Text(
              'Message:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(message),
            ),

            SizedBox(height: 16),

            // Action buttons
            if (status == 'pending')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _showConfirmationDialog(
                      applicationId,
                      'rejected',
                      'Reject Application',
                      'Are you sure you want to reject this application from $name?',
                      Colors.red,
                    ),
                    child: Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _showConfirmationDialog(
                      applicationId,
                      'approved',
                      'Approve Application',
                      'Are you sure you want to approve this application from $name?',
                      Colors.green,
                    ),
                    child: Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Show confirmation dialog before updating application status
  Future<void> _showConfirmationDialog(
      String applicationId,
      String newStatus,
      String title,
      String message,
      Color confirmColor,
      ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(message),
                SizedBox(height: 10),
                Text(
                  'This action cannot be undone.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                newStatus == 'approved' ? 'Approve' : 'Reject',
                style: TextStyle(color: confirmColor),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _updateApplicationStatus(applicationId, newStatus);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, String? actionType) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  if (actionType == null)
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[800],
                      ),
                    )
                  else
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          if (actionType == 'email') {
                            _launchEmail(value);
                          } else if (actionType == 'contact') {
                            _showContactOptions(value);
                          }
                        },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _launchEmail(String email) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: email,
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch email app')),
      );
    }
  }

  void _showContactOptions(String contact) {
    // Check if the contact is a valid phone number
    // This is a simple validation, improve as needed
    bool isPhoneNumber = contact.replaceAll(RegExp(r'[^\d+]'), '').isNotEmpty;

    if (!isPhoneNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid contact information')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.phone),
                title: Text('Call'),
                onTap: () {
                  Navigator.of(context).pop();
                  _launchDialer(contact);
                },
              ),
              ListTile(
                leading: Icon(Icons.message),
                title: Text('SMS'),
                onTap: () {
                  Navigator.of(context).pop();
                  _launchSMS(contact);
                },
              ),
              ListTile(
                leading: Icon(Icons.chat),
                title: Text('WhatsApp'),
                onTap: () {
                  Navigator.of(context).pop();
                  _launchWhatsApp(contact);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _launchDialer(String phoneNumber) async {
    final Uri uri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch phone app')),
      );
    }
  }

  void _launchSMS(String phoneNumber) async {
    final Uri uri = Uri(
      scheme: 'sms',
      path: phoneNumber,
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch SMS app')),
      );
    }
  }

  void _launchWhatsApp(String phoneNumber) async {
    // Format the phone number by removing any non-digit characters
    String formattedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // WhatsApp deeplink
    final Uri uri = Uri.parse('https://wa.me/$formattedNumber');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch WhatsApp')),
      );
    }
  }

  Future<void> _updateApplicationStatus(String applicationId, String newStatus) async {
    try {
      // Update the application status
      await _firestore.collection('event_applications').doc(applicationId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Application ${newStatus == 'approved' ? 'approved' : 'rejected'} successfully'),
          backgroundColor: newStatus == 'approved' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating application status: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}