import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth

class AdminPaymentsPage extends StatefulWidget {
  final String? eventId;

  const AdminPaymentsPage({Key? key, this.eventId}) : super(key: key);

  @override
  _AdminPaymentsPageState createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  bool _isLoading = false;
  bool _isOrganizer = false; // Track if current user is an organizer
  List<Map<String, dynamic>> _payments = [];
  String? _selectedEventName;
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  // First check if the user is an organizer
  Future<void> _checkUserRole() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the current user
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        // Handle not logged in case
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to view this page')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Check if user has organizer role
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data()?['role'] == 'Organizer') {
        setState(() {
          _isOrganizer = true;
        });

        // Now we can fetch event name and payments
        _fetchEventName();
        _fetchPayments();
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You do not have permission to view payments')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking permissions: $e')),
      );
    }
  }

  Future<void> _fetchEventName() async {
    if (widget.eventId == null) return;

    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (eventDoc.exists) {
        setState(() {
          _selectedEventName = (eventDoc.data() as Map<String, dynamic>)['name'] ?? 'Unknown Event';
        });
      }
    } catch (e) {
      print('Error fetching event name: $e');
    }
  }

  Future<void> _fetchPayments() async {
    // Only proceed if user is an organizer
    if (!_isOrganizer) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance.collection('payments')
          .orderBy('timestamp', descending: true);

      if (widget.eventId != null) {
        query = query.where('eventId', isEqualTo: widget.eventId);
      }

      final QuerySnapshot paymentDocs = await query.get();

      final List<Map<String, dynamic>> paymentsList = [];

      for (var doc in paymentDocs.docs) {
        final payment = doc.data() as Map<String, dynamic>;
        payment['id'] = doc.id;

        if (payment['eventName'] == null) {
          try {
            final eventDoc = await FirebaseFirestore.instance
                .collection('events')
                .doc(payment['eventId'])
                .get();

            if (eventDoc.exists) {
              final eventData = eventDoc.data() as Map<String, dynamic>;
              payment['eventName'] = eventData['name'] ?? 'Unknown Event';
            } else {
              payment['eventName'] = 'Unknown Event';
            }
          } catch (e) {
            payment['eventName'] = 'Error Loading Event';
          }
        }

        paymentsList.add(payment);
      }

      setState(() {
        _payments = paymentsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading payments: $e')),
      );
    }
  }


  Future<void> _verifyPayment(String paymentId, bool isVerified) async {
    // Only proceed if user is an organizer
    if (!_isOrganizer) return;

    try {
      final FirebaseFirestore _firestore = FirebaseFirestore.instance;

      // Get the payment document first to access necessary fields
      final paymentDoc = await _firestore.collection('payments').doc(paymentId).get();
      final payment = paymentDoc.data();

      if (payment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment data not found')),
        );
        return;
      }

      // Use a transaction to ensure atomic operations
      await _firestore.runTransaction((transaction) async {
        // IMPORTANT: Perform ALL reads first

        // Read the payment document
        final paymentDocInTransaction = await transaction.get(
            _firestore.collection('payments').doc(paymentId)
        );

        // Read the event document
        final eventDocRef = _firestore.collection('events').doc(payment['eventId']);
        final eventDoc = await transaction.get(eventDocRef);
        final currentTicketsClaimed = eventDoc.data()?['ticketsClaimed'] as int? ?? 0;

        // After all reads are complete, now perform the writes

        // Update the payment document
        transaction.update(_firestore.collection('payments').doc(paymentId), {
          'isVerified': isVerified,
          'verifiedAt': isVerified ? FieldValue.serverTimestamp() : null,
        });

        // Update the event document - increment or decrement ticketsClaimed
        transaction.update(eventDocRef, {
          'ticketsClaimed': isVerified
              ? currentTicketsClaimed + 1
              : (currentTicketsClaimed - 1).clamp(0, double.infinity).toInt(),
        });

        if (isVerified) {
          // Create a record in the claimed_tickets collection when verifying
          final claimedTicketRef = _firestore.collection('claimed_tickets').doc();
          transaction.set(claimedTicketRef, {
            'eventId': payment['eventId'],
            'userId': payment['userId'],
            'userEmail': payment['userEmail'] ?? 'Unknown Email',
            'claimedAt': FieldValue.serverTimestamp(),
            'ticketId': claimedTicketRef.id,
            'eventName': payment['eventName'] ?? 'Unnamed Event',
            'paymentId': paymentId, // Reference to the payment
            'isPaid': true, // Flag to differentiate from free tickets
          });
        } else {
          // Remove from claimed_tickets when unverifying
          final claimedTicketsQuery = await _firestore.collection('claimed_tickets')
              .where('paymentId', isEqualTo: paymentId)
              .get();

          for (var doc in claimedTicketsQuery.docs) {
            transaction.delete(doc.reference);
          }
        }
      });

      // Refresh payments
      _fetchPayments();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isVerified
            ? 'Payment verified and ticket issued to user'
            : 'Payment verification removed and ticket revoked')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating payment: $e')),
      );
    }
  }

  void _viewPaymentDetails(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Payment Details',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailItem('Event', payment['eventName']),
                      _buildDetailItem('Payment ID', payment['id']),
                      _buildDetailItem('Date', _formatTimestamp(payment['timestamp'])),

                      if (payment.containsKey('userId'))
                        _buildDetailItem('User ID', payment['userId']),

                      if (payment.containsKey('notes'))
                        _buildDetailItem('Notes', payment['notes']),

                      const SizedBox(height: 16),
                      const Text(
                        'Payment Screenshot',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: payment['screenshotUrl'],
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.error),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Show both buttons if status is pending (isVerified is null)
                  if (payment['isVerified'] == null) ...[
                    SizedBox(
                      width: 120,
                      child: ElevatedButton(
                        onPressed: _isOrganizer
                            ? () {
                          _verifyPayment(payment['id'], true);
                          Navigator.of(context).pop();
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Verify Payment'),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: ElevatedButton(
                        onPressed: _isOrganizer
                            ? () {
                          _verifyPayment(payment['id'], false);
                          Navigator.of(context).pop();
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Reject Payment'),
                      ),
                    ),
                  ] else ...[
                    // Show single toggle button if status is verified or unverified
                    SizedBox(
                      width: 120,
                      child: ElevatedButton(
                        onPressed: _isOrganizer
                            ? () {
                          _verifyPayment(payment['id'], !(payment['isVerified'] ?? false));
                          Navigator.of(context).pop();
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (payment['isVerified'] ?? false)
                              ? Colors.orange
                              : Colors.blue,
                        ),
                        child: Text((payment['isVerified'] ?? false)
                            ? 'Unverify Payment'
                            : 'Mark as Verified'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';

    if (timestamp is Timestamp) {
      return _dateFormat.format(timestamp.toDate());
    }

    return 'Invalid Date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventId != null
            ? 'Payments for ${_selectedEventName ?? "Event"}'
            : 'Payment Submissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isOrganizer ? _fetchPayments : null,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isOrganizer
          ? Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _payments.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    widget.eventId != null
                        ? 'No payments for this event yet'
                        : 'No payment submissions found',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _payments.length,
              itemBuilder: (context, index) {
                final payment = _payments[index];
                final bool isVerified = payment['isVerified'] ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isVerified ?
                      Colors.green :
                      (payment.containsKey('isVerified') ? Colors.red : Colors.grey),
                      child: Icon(
                        isVerified ?
                        Icons.check :
                        (payment.containsKey('isVerified') ? Icons.close : Icons.pending),
                        color: Colors.white,
                      ),
                    ),
                    title: widget.eventId == null
                        ? Text(payment['eventName'])
                        : null,
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Submitted: ${_formatTimestamp(payment['timestamp'])}'),
                        if (payment.containsKey('userId'))
                          Text('User ID: ${payment['userId']}'),
                        Text(
                          'Status: ${isVerified ? 'Verified' : (payment.containsKey('isVerified') ? 'Unverified' : 'Pending')}',
                          style: TextStyle(
                              color: isVerified ?
                              Colors.green :
                              (payment.containsKey('isVerified') ? Colors.red : Colors.grey),
                              fontWeight: FontWeight.bold
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: payment['screenshotUrl'],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          onPressed: () => _viewPaymentDetails(payment),
                          tooltip: 'View Details',
                        ),
                      ],
                    ),
                    onTap: () => _viewPaymentDetails(payment),
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total submissions: ${_payments.length}'),
                Text(
                  'Verified: ${_payments.where((p) => p['isVerified'] == true).length}',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      )
          : const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'You do not have permission to view this page',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Only users with organizer role can access payment submissions',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}