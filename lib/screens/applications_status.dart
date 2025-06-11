import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MyApplicationsPage extends StatefulWidget {
  const MyApplicationsPage({Key? key}) : super(key: key);

  @override
  _MyApplicationsPageState createState() => _MyApplicationsPageState();
}

class _MyApplicationsPageState extends State<MyApplicationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Applications'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getApplicationsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading applications'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No applications found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You haven\'t applied for any events yet',
                    style: TextStyle(color: Colors.grey[600]),
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
    // Ensure there's a logged-in user
    final user = _auth.currentUser;
    if (user == null) {
      // Return an empty stream if no user is logged in
      return Stream.empty(); // This is the correct way to return an empty stream
    }

    return _firestore
        .collection('event_applications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('appliedAt', descending: true)
        .snapshots();
  }

  Widget _buildApplicationCard(Map<String, dynamic> application, String applicationId) {
    final String eventName = application['eventName'] ?? 'Unknown Event';
    final String role = application['role'] ?? 'Unknown role';
    final String status = application['status'] ?? 'pending';
    final Timestamp? appliedAt = application['appliedAt'] as Timestamp?;
    final String message = application['message'] ?? 'No message provided';

    final String formattedDate = appliedAt != null
        ? DateFormat('MMM dd, yyyy - hh:mm a').format(appliedAt.toDate())
        : 'Unknown date';

    // Determine status color and icon
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending Review';
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event name and application date
            Row(
              children: [
                Expanded(
                  child: Text(
                    eventName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),

            // Role applied for
            Row(
              children: [
                Icon(Icons.work, size: 16, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  'Applied as: ',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                Text(
                  role,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Application status
            Container(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),

            // Message
            ExpansionTile(
              title: Text(
                'Your Message',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(message),
                ),
              ],
            ),

            SizedBox(height: 8),

            // Delete button
            Align(
              alignment: Alignment.centerRight,
              child: status == 'pending'
                  ? TextButton.icon(
                icon: Icon(Icons.delete_outline, color: Colors.red),
                label: Text('Cancel Application'),
                onPressed: () => _confirmDeleteApplication(applicationId, eventName),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              )
                  : SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteApplication(String applicationId, String eventName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Cancel Application'),
          content: Text('Are you sure you want to cancel your application for "$eventName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteApplication(applicationId);
              },
              child: Text('Yes, Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteApplication(String applicationId) async {
    try {
      await _firestore.collection('event_applications').doc(applicationId).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Application cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cancelling application: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}